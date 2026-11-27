import SwiftUI
import AppKit

struct Repo: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct Banner: Equatable { let text: String; let isError: Bool }

struct Workspace: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var repos: [String] = []   // repo folder paths
}

@MainActor
final class Store: ObservableObject {
    /// Folders whose direct sub-folders are scanned for repos. The "All repos" view is everything found here.
    @Published var roots: [String] { didSet { save() } }
    @Published var workspaces: [Workspace] { didSet { save() } }
    @Published var extraRepos: [String] { didSet { save() } }   // single repos added from outside the roots
    @Published var current: String? { didSet { save(); fixSelection() } }   // workspace id; nil = All repos
    @Published var allRepos: [Repo] = []
    @Published var selected: Repo.ID?
    @Published var statuses: [String: RepoStatus] = [:]
    @Published var messages: [String: String] = [:]
    @Published var ticked: [String: Set<String>] = [:]
    @Published var banner: Banner?
    @Published var side: [String: SideInfo] = [:]
    @Published var showClone = false
    @Published var revision: [String: Int] = [:]   // bumps after every full reload, so open panes can re-read
    @Published var focusRequest: String?   // a file the tree asks the repo page to show
    @Published var trees: [String: [FileNode]] = [:]
    @Published var treeTruncated: Set<String> = []
    @Published var busy = false
    @Published var scanning = false
    @Published var syncing = false
    @Published var syncTags: [String: SyncTag] = [:]   // repos the last sync left alone, and why
    private var seen: [String: Set<String>] = [:]

    /// Set only by the headless self-test: use a throw-away folder and never write the saved settings.
    static var captureRoot: String?

    init() {
        let d = UserDefaults.standard
        var r = d.stringArray(forKey: "roots") ?? []
        if r.isEmpty { r = [d.string(forKey: "workspace") ?? (NSHomeDirectory() + "/Desktop/repos")] }
        roots = r
        extraRepos = d.stringArray(forKey: "extraRepos") ?? []
        workspaces = (d.data(forKey: "workspaces").flatMap { try? JSONDecoder().decode([Workspace].self, from: $0) }) ?? []
        current = d.string(forKey: "current")
        if let c = Store.captureRoot { roots = [c]; extraRepos = []; workspaces = []; current = nil }
    }

    private func save() {
        if Store.captureRoot != nil { return }
        let d = UserDefaults.standard
        d.set(roots, forKey: "roots"); d.set(extraRepos, forKey: "extraRepos"); d.set(current, forKey: "current")
        d.set(try? JSONEncoder().encode(workspaces), forKey: "workspaces")
    }

    var currentWorkspace: Workspace? { current.flatMap { id in workspaces.first { $0.id == id } } }
    var currentName: String { currentWorkspace?.name ?? "All repos" }
    /// The repos shown in the sidebar: everything, or only the repos of the chosen workspace.
    var repos: [Repo] {
        guard let w = currentWorkspace else { return allRepos }
        return allRepos.filter { w.repos.contains($0.id) }
    }
    var selectedRepo: Repo? { repos.first { $0.id == selected } }

    func count(in w: Workspace?) -> Int { w == nil ? allRepos.count : allRepos.filter { w!.repos.contains($0.id) }.count }

    private func fixSelection() {
        if !repos.contains(where: { $0.id == selected }) { selected = repos.first?.id }
    }

    // MARK: folders and repos
    private func isRepo(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.appendingPathComponent(".git").path) }

    /// Pick a folder. A git repo is added as one repo (to the current workspace, if one is chosen);
    /// any other folder is added as a repos folder and every repo inside it is found.
    func addPath() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        p.prompt = "Add"; p.message = "Choose a git repo, or a folder that holds your repos"
        guard p.runModal() == .OK else { return }
        for u in p.urls {
            if isRepo(u) {
                if !roots.contains(u.deletingLastPathComponent().path) && !extraRepos.contains(u.path) { extraRepos.append(u.path) }
                if var w = currentWorkspace, !w.repos.contains(u.path) { w.repos.append(u.path); update(w) }
            } else if !roots.contains(u.path) { roots.append(u.path) }
        }
        Task { await scan() }
    }

    /// Replace one repos folder with another (the "update the path" action).
    func changeRoot(_ old: String) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.prompt = "Use folder"; p.directoryURL = URL(fileURLWithPath: old)
        guard p.runModal() == .OK, let u = p.url, let i = roots.firstIndex(of: old) else { return }
        roots[i] = u.path
        Task { await scan() }
    }
    func removeRoot(_ path: String) { roots.removeAll { $0 == path }; Task { await scan() } }

    // MARK: workspaces
    func update(_ w: Workspace) { if let i = workspaces.firstIndex(where: { $0.id == w.id }) { workspaces[i] = w } }
    func newWorkspace(named n: String) {
        let name = n.trimmingCharacters(in: .whitespaces); guard !name.isEmpty else { return }
        let w = Workspace(name: name); workspaces.append(w); current = w.id
    }
    func rename(_ w: Workspace, to n: String) {
        let name = n.trimmingCharacters(in: .whitespaces); guard !name.isEmpty else { return }
        var x = w; x.name = name; update(x)
    }
    func delete(_ w: Workspace) { workspaces.removeAll { $0.id == w.id }; if current == w.id { current = nil } }
    func isIn(_ repo: Repo, _ w: Workspace) -> Bool { w.repos.contains(repo.id) }
    func toggleMember(_ repo: Repo, _ w: Workspace) {
        var x = w
        if x.repos.contains(repo.id) { x.repos.removeAll { $0 == repo.id } } else { x.repos.append(repo.id) }
        update(x); fixSelection()
    }

    /// 01-workspace: every direct sub-folder of a repos folder that holds a .git entry is a repo, plus single repos added by hand.
    func scan() async {
        scanning = true
        let fm = FileManager.default
        var urls: [URL] = []
        for root in roots {
            let subs = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            urls += subs.filter { u in
                var d: ObjCBool = false
                return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue && isRepo(u)
            }
        }
        urls += extraRepos.map { URL(fileURLWithPath: $0) }.filter { isRepo($0) }
        var seenPaths = Set<String>()
        let found = urls.map { Repo(url: $0) }.filter { seenPaths.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allRepos = found
        fixSelection()
        await withTaskGroup(of: Void.self) { g in
            for r in found { g.addTask { await self.refresh(r, fetch: true) } }
        }
        if let r = selectedRepo { await reload(r) }
        scanning = false
    }

    /// 02-repo: status, then line counts.
    /// Runs `work` while holding the repo's gate, so network git jobs on one repo never overlap.
    func gated<T>(_ repo: Repo, _ work: () async -> T) async -> T {
        await RepoGate.shared.acquire(repo.id)
        let r = await work()
        await RepoGate.shared.release(repo.id)
        return r
    }

    /// A fetch that leaves FETCH_HEAD alone (so it cannot confuse a pull) and never overlaps another job on the repo.
    func fetchRemote(_ repo: Repo, remote: String? = nil) async -> GitResult {
        await gated(repo) { await Git.run(["fetch", "--quiet", "--prune", "--no-write-fetch-head"] + (remote.map { [$0] } ?? []), in: repo.url, timeout: 30) }
    }

    /// Reads the repo's status (fast), then, when asked, fetches from the remote and reads it again so the pull count is true.
    func refresh(_ repo: Repo, fetch: Bool = false) async {
        await readStatus(repo)
        if fetch {
            _ = await fetchRemote(repo)
            await readStatus(repo)
        }
    }

    /// Everything the screen shows about a repo, brought up to date together: status and counts, the right-hand panel
    /// (commits, branches, pull requests) and the file tree. Every action ends with this, so no panel is left stale.
    func reload(_ repo: Repo, fetch: Bool = false) async {
        await refresh(repo, fetch: fetch)
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadSide(repo) }
            g.addTask { await self.loadTree(repo) }
        }
        revision[repo.id, default: 0] += 1
    }

    func readStatus(_ repo: Repo) async {
        let r = await Git.run(["--no-optional-locks", "status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"], in: repo.url)
        guard r.ok else { setError("\(repo.name): \(r.text)"); return }
        var st = StatusParser.parse(r.out)
        let ns = await Git.run(["--no-optional-locks", "diff", "HEAD", "--numstat"], in: repo.url)
        let counts = ns.ok ? StatusParser.numstat(ns.out) : [:]
        for i in st.changes.indices {
            if let c = counts[st.changes[i].path] {
                st.changes[i].added = c.0; st.changes[i].deleted = c.1; st.changes[i].binary = c.2
            }
        }
        statuses[repo.id] = st
        let known = seen[repo.id] ?? []
        var t = (ticked[repo.id] ?? []).intersection(Set(st.changes.map(\.path)))
        for c in st.changes where !known.contains(c.path) && !c.isSecret { t.insert(c.path) }
        ticked[repo.id] = t
        seen[repo.id] = known.union(st.changes.map(\.path))
    }

    /// Right sidebar: branches, commits not yet local, commits not yet pushed, pull requests.
    func loadSide(_ repo: Repo) async {
        var info = side[repo.id] ?? SideInfo()
        let b = await Git.run(["for-each-ref", "--format=%(HEAD)%09%(refname)%09%(refname:short)%09%(upstream:track)%09%(upstream:short)", "refs/heads", "refs/remotes"], in: repo.url)
        var locals = Set<String>()
        if b.ok { info.branches = SideParser.branches(b.out, locals: &locals) }
        let fmt = "--format=%h%x09%an%x09%ar%x09%s"
        let inc = await Git.run(["log", fmt, "-50", "HEAD..@{u}"], in: repo.url)
        info.incoming = inc.ok ? SideParser.commits(inc.out) : []
        let out = await Git.run(["log", fmt, "-50", "@{u}..HEAD"], in: repo.url)
        info.outgoing = out.ok ? SideParser.commits(out.out) : []
        side[repo.id] = info
        // Pull requests need the GitHub CLI; it is optional.
        let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let gh else { info.prs = []; info.prNote = "Install the GitHub CLI (brew install gh) to list pull requests."; side[repo.id] = info; return }
        let r = await Git.exec(gh, ["pr", "list", "--json", "number,title,headRefName,author,url,isDraft", "--limit", "30"], in: repo.url)
        if r.ok, let prs = try? JSONDecoder().decode([PullRequest].self, from: Data(r.out.utf8)) { info.prs = prs; info.prNote = prs.isEmpty ? "No open pull requests." : nil }
        else {
            info.prs = []
            let t = r.text.lowercased()
            info.prNote = t.contains("auth") || t.contains("login") ? "Run gh auth login in Terminal to list pull requests." : (t.contains("github") || t.contains("remote") ? "No GitHub remote for this repo." : "Could not list pull requests.")
        }
        side[repo.id] = info
    }

    // MARK: deleting branches
    /// Branches that are never deleted from here: main, master and the remote's default branch.
    func protectedNames(_ repo: Repo) async -> Set<String> {
        var out: Set<String> = ["main", "master"]
        let r = await Git.run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: repo.url)
        if r.ok { let t = r.out.trimmingCharacters(in: .whitespacesAndNewlines); out.insert(String(t.drop(while: { $0 != "/" }).dropFirst())) }
        return out
    }

    struct BranchFacts { var isProtected = false; var unmerged: Int? = nil; var base = ""; var openPR: PullRequest? = nil }

    /// What to tell the person before a branch is deleted: is it protected, how many commits exist only on it, which pull request uses it.
    func branchFacts(_ repo: Repo, _ b: BranchInfo) async -> BranchFacts {
        var f = BranchFacts()
        let short = b.isRemote ? (b.remoteBranch ?? b.name) : b.name
        f.isProtected = await protectedNames(repo).contains(short)
        let head = await Git.run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: repo.url)
        var base = head.ok ? head.out.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if base.isEmpty { base = (await Git.run(["rev-parse", "--verify", "-q", "origin/main"], in: repo.url)).ok ? "origin/main" : "main" }
        f.base = base
        let ref = b.isRemote ? b.name : b.name
        let n = await Git.run(["rev-list", "--count", "\(base)..\(ref)"], in: repo.url)
        f.unmerged = n.ok ? Int(n.out.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        f.openPR = side[repo.id]?.prs.first { $0.headRefName == short }
        return f
    }

    /// `git branch -d` refuses a branch with commits that are not merged; `force` uses -D. Returns the error text or nil.
    func deleteLocalBranch(_ repo: Repo, _ name: String, force: Bool) async -> String? {
        let r = await Git.run(["branch", force ? "-D" : "-d", "--", name], in: repo.url)
        await reload(repo)
        return r.ok ? nil : r.text
    }

    /// `git push <remote> --delete <branch>`, then a pruning fetch so the list is current. Returns the error text or nil.
    func deleteRemoteBranch(_ repo: Repo, _ remote: String, _ branch: String) async -> String? {
        let r = await gated(repo) { await Git.run(["push", remote, "--delete", branch], in: repo.url) }
        _ = await fetchRemote(repo, remote: remote)
        await reload(repo)
        return r.ok ? nil : r.text
    }

    func switchBranch(_ repo: Repo, _ b: BranchInfo) async {
        busy = true; defer { busy = false }
        let r = await Git.run(["switch", b.switchName], in: repo.url)
        r.ok ? setInfo("Switched to \(b.switchName).") : setError(r.text)
        await reload(repo)
    }

    func checkoutPR(_ repo: Repo, _ pr: PullRequest) async {
        guard let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        busy = true; defer { busy = false }
        let r = await Git.exec(gh, ["pr", "checkout", String(pr.number)], in: repo.url)
        r.ok ? setInfo("Checked out #\(pr.number).") : setError(r.text)
        await reload(repo)
    }

    func toggle(_ repo: Repo, _ path: String) {
        var t = ticked[repo.id] ?? []
        if t.contains(path) { t.remove(path) } else { t.insert(path) }
        ticked[repo.id] = t
    }

    func setTicked(_ repo: Repo, _ paths: [String], on: Bool) {
        var t = ticked[repo.id] ?? []
        if on { t.formUnion(paths) } else { t.subtract(paths) }
        ticked[repo.id] = t
    }

    func diff(_ repo: Repo, _ c: Change) async -> String {
        if c.binary { return "Binary file. No text diff." }
        if c.untracked {
            let u = repo.url.appendingPathComponent(c.path)
            guard let d = try? Data(contentsOf: u, options: .mappedIfSafe) else { return "Could not read \(c.path)." }
            if d.prefix(8000).contains(0) { return "Binary file. No text diff." }
            let lines = String(decoding: d.prefix(200_000), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            return "New file, not tracked yet.\n" + lines.prefix(2000).map { "+" + $0 }.joined(separator: "\n")
        }
        var r = await Git.run(["diff", "HEAD", "--no-color", "--", c.path], in: repo.url)
        if !r.ok { r = await Git.run(["diff", "--cached", "--no-color", "--", c.path], in: repo.url) }
        let t = r.out.split(separator: "\n", omittingEmptySubsequences: false).prefix(2000).joined(separator: "\n")
        return t.isEmpty ? "No text changes." : t
    }

    func commit(_ repo: Repo) async {
        let msg = (messages[repo.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = Array(ticked[repo.id] ?? []).sorted()
        guard !msg.isEmpty, !paths.isEmpty else { return }
        busy = true; defer { busy = false }
        _ = await Git.run(["reset", "-q"], in: repo.url)
        let add = await Git.run(["add", "-A", "--"] + paths, in: repo.url)
        guard add.ok else { setError(add.text); return }
        let c = await Git.run(["commit", "-m", msg], in: repo.url)
        if c.ok {
            messages[repo.id] = ""
            setInfo("Committed \(paths.count) file\(paths.count == 1 ? "" : "s").")
        } else { setError(c.text) }
        await reload(repo)
    }

    /// Pull = fetch, then fast-forward to the upstream branch by name. It does not use `git pull`, which merges whatever is
    /// in FETCH_HEAD and failed with "Cannot fast-forward to multiple branches" when another fetch overlapped it.
    func pull(_ repo: Repo) async {
        busy = true; defer { busy = false }
        let err: String? = await gated(repo) {
            let head = await Git.run(["symbolic-ref", "-q", "HEAD"], in: repo.url)
            guard head.ok else { return "You are not on a branch, so there is nothing to pull." }
            let ref = head.out.trimmingCharacters(in: .whitespacesAndNewlines)
            let rn = await Git.run(["for-each-ref", "--format=%(upstream:remotename)", ref], in: repo.url)
            let remote = rn.out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remote.isEmpty else { return "This branch has no upstream branch to pull from." }
            let f = await Git.run(["fetch", "--quiet", "--prune", remote], in: repo.url, timeout: 60)
            guard f.ok else { return f.text }
            let m = await Git.run(["merge", "--ff-only", "@{upstream}"], in: repo.url)
            if !m.ok { return m.text }
            self.pullNote = m.text
            return nil
        }
        if let err { setError(err) } else { syncTags[repo.id] = nil; setInfo(lastLine(pullNote.isEmpty ? "Pulled." : pullNote)) }
        await reload(repo)
    }
    private var pullNote = ""

    func push(_ repo: Repo) async {
        busy = true; defer { busy = false }
        let st = statuses[repo.id]
        var args = ["push"]
        if st?.upstream == nil, let b = st?.branch, !b.isEmpty { args = ["push", "-u", "origin", b] }
        let r = await gated(repo) { await Git.run(args, in: repo.url, timeout: 120) }
        if r.ok { syncTags[repo.id] = nil }
        r.ok ? setInfo("Pushed.") : setError(r.text)
        await reload(repo)
    }

    // MARK: Sync a whole workspace

    /// What one repo's sync did. A skipped repo was not changed at all.
    enum SyncOutcome: Sendable, Equatable {
        case upToDate
        case pulled(Int)
        case pushed(Int)
        case skipped(SyncTag)
    }
    struct SyncTag: Sendable, Equatable {
        let label: String    // short, shown in the sidebar
        let detail: String   // the reason, shown on hover and on the repo page
    }
    struct SyncSummary: Equatable { var pulled = 0, pushed = 0, current = 0, skipped = 0, total = 0 }

    /// Syncs the repos in the chosen workspace (or all repos): fast-forward pull, then push what is ahead.
    func syncCurrent() async { _ = await syncRepos(repos, scope: currentName) }

    /// A repo is only changed when that cannot conflict. Anything that could (a merge or rebase in progress, unmerged files,
    /// diverged branches, local edits to files the remote also changed, no upstream, detached HEAD, a failed fetch) is left
    /// exactly as it is and gets a tag in the sidebar.
    func syncRepos(_ list: [Repo], scope: String) async -> SyncSummary {
        guard !syncing else { return SyncSummary() }
        syncing = true; busy = true
        defer { syncing = false; busy = false }
        for r in list { syncTags[r.id] = nil }
        var sum = SyncSummary(); sum.total = list.count
        var it = list.makeIterator()
        await withTaskGroup(of: (Repo, SyncOutcome).self) { g in
            var running = 0
            while running < 4, let r = it.next() { g.addTask { (r, await self.syncOne(r)) }; running += 1 }
            while let (r, o) = await g.next() {
                switch o {
                case .upToDate: sum.current += 1
                case .pulled: sum.pulled += 1
                case .pushed: sum.pushed += 1
                case .skipped(let t): sum.skipped += 1; syncTags[r.id] = t
                }
                if let r2 = it.next() { g.addTask { (r2, await self.syncOne(r2)) } }
            }
        }
        if let r = selectedRepo, list.contains(where: { $0.id == r.id }) { await reload(r) }
        var parts: [String] = []
        if sum.pulled > 0 { parts.append("pulled \(sum.pulled)") }
        if sum.pushed > 0 { parts.append("pushed \(sum.pushed)") }
        if sum.current > 0 { parts.append("\(sum.current) already up to date") }
        var msg = "\(scope): synced \(sum.total - sum.skipped) of \(sum.total) repo\(sum.total == 1 ? "" : "s")" + (parts.isEmpty ? "." : " (" + parts.joined(separator: ", ") + ").")
        if sum.skipped > 0 { msg += " \(sum.skipped) left untouched: see the tags in the list." }
        setInfo(msg)
        return sum
    }

    func syncOne(_ repo: Repo) async -> SyncOutcome {
        let outcome: SyncOutcome = await gated(repo) {
            let dir = repo.url
            func skip(_ label: String, _ detail: String) -> SyncOutcome { .skipped(SyncTag(label: label, detail: detail)) }
            // 1. Read-only checks first.
            let gd = await Git.run(["rev-parse", "--absolute-git-dir"], in: dir)
            if gd.ok {
                let g = gd.out.trimmingCharacters(in: .whitespacesAndNewlines)
                let busyFiles = ["MERGE_HEAD": "a merge", "rebase-merge": "a rebase", "rebase-apply": "a rebase", "CHERRY_PICK_HEAD": "a cherry-pick", "REVERT_HEAD": "a revert"]
                for (f, what) in busyFiles where FileManager.default.fileExists(atPath: g + "/" + f) {
                    return skip("Conflicts", "Left alone: \(what) is in progress. Finish or abort it first.")
                }
            }
            await self.readStatus(repo)
            guard let st0 = self.statuses[repo.id] else { return skip("Unreadable", "Left alone: git could not read this repo.") }
            if st0.changes.contains(where: { $0.x == "U" || $0.y == "U" || ($0.x == "A" && $0.y == "A") || ($0.x == "D" && $0.y == "D") }) {
                return skip("Conflicts", "Left alone: it has unresolved merge conflicts.")
            }
            let head = await Git.run(["symbolic-ref", "-q", "HEAD"], in: dir)
            guard head.ok else { return skip("Detached", "Left alone: you are not on a branch.") }
            let ref = head.out.trimmingCharacters(in: .whitespacesAndNewlines)
            let rn = await Git.run(["for-each-ref", "--format=%(upstream:remotename)", ref], in: dir)
            let remote = rn.out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remote.isEmpty else { return skip("No upstream", "Left alone: this branch has no upstream branch to sync with.") }
            // 2. Fetch (never writes FETCH_HEAD), then look again.
            let f = await Git.run(["fetch", "--quiet", "--prune", "--no-write-fetch-head", remote], in: dir, timeout: 60)
            guard f.ok else { return skip("Fetch failed", "Left alone: \(self.lastLine(f.text))") }
            await self.readStatus(repo)
            guard let st = self.statuses[repo.id] else { return skip("Unreadable", "Left alone: git could not read this repo.") }
            if st.ahead > 0 && st.behind > 0 {
                return skip("Diverged", "Left alone: \(st.ahead) local and \(st.behind) remote commit\(st.behind == 1 ? "" : "s") not in each other. Merge or rebase it yourself.")
            }
            // 3. Behind: pull only when local edits do not touch the files the remote changed.
            if st.behind > 0 {
                let d = await Git.run(["diff", "--name-only", "-z", "HEAD", "@{upstream}"], in: dir)
                let incoming = d.ok ? d.out.split(separator: "\0").map(String.init) : []
                let local = st.changes.map(\.path)
                let hits = incoming.filter { i in local.contains { l in l == i || l.hasPrefix(i + "/") || i.hasPrefix(l + "/") } }
                if !d.ok { return skip("Unreadable", "Left alone: could not compare with the remote.") }
                if !hits.isEmpty {
                    let names = hits.prefix(3).joined(separator: ", ") + (hits.count > 3 ? " and \(hits.count - 3) more" : "")
                    return skip("Would conflict", "Left alone: you changed \(names), and the remote changed \(hits.count == 1 ? "it" : "them") too. Commit or discard your edits, then pull.")
                }
                let m = await Git.run(["merge", "--ff-only", "@{upstream}"], in: dir)
                guard m.ok else { return skip("Pull failed", "Left alone: \(self.lastLine(m.text))") }
                await self.readStatus(repo)
                return .pulled(st.behind)
            }
            // 4. Ahead: push.
            if st.ahead > 0 {
                let p = await Git.run(["push"], in: dir, timeout: 120)
                guard p.ok else { return skip("Push failed", "Not pushed: \(self.lastLine(p.text))") }
                await self.readStatus(repo)
                return .pushed(st.ahead)
            }
            return .upToDate
        }
        return outcome
    }

    /// Throws away local changes in the files and in the list: new staged files are removed, other tracked files go back
    /// to HEAD, untracked files are deleted. The rows disappear at once, then the real status is re-read.
    func discard(_ repo: Repo, _ cs: [Change]) async {
        busy = true; defer { busy = false }
        var errors: [String] = []
        let added = cs.filter { !$0.untracked && $0.x == "A" }.map(\.path)
        let tracked = cs.filter { !$0.untracked && $0.x != "A" }.map(\.path)
        let fresh = cs.filter { $0.untracked }.map(\.path)
        if !added.isEmpty {
            let r = await Git.run(["rm", "-r", "-f", "-q", "--"] + added, in: repo.url)
            if !r.ok { errors.append(r.text) }
        }
        if !tracked.isEmpty {
            var r = await Git.run(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + tracked, in: repo.url)
            if !r.ok { // retry one by one so one bad path does not block the rest
                for t in tracked {
                    r = await Git.run(["restore", "--source=HEAD", "--staged", "--worktree", "--", t], in: repo.url)
                    if !r.ok { errors.append(r.text) }
                }
            }
        }
        if !fresh.isEmpty {
            // Untracked paths go to the Trash (recoverable). This also handles folders that are repos themselves,
            // which `git clean -f` skips. If the Trash fails, force-clean as a fallback.
            for path in fresh {
                let u = repo.url.appendingPathComponent(path)
                do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) }
                catch {
                    let r = await Git.run(["clean", "-f", "-f", "-d", "-q", "--", path], in: repo.url)
                    if !r.ok { errors.append(r.text) }
                }
            }
        }
        // Remove the rows now, whatever happened; the refresh below puts back anything that really is still changed.
        let gone = Set(cs.map(\.path))
        if var st = statuses[repo.id] { st.changes.removeAll { gone.contains($0.path) }; statuses[repo.id] = st }
        ticked[repo.id] = (ticked[repo.id] ?? []).subtracting(gone)
        await reload(repo)
        if let e = errors.first { setError(e) } else { setInfo("Discarded \(cs.count) change\(cs.count == 1 ? "" : "s").") }
    }

    /// Adds patterns to the repo's .gitignore. Paths git already tracks are only ignored once they are untracked,
    /// so `untrack` lists paths to take out of the index (`git rm --cached`; the files stay on disk).
    func ignore(_ repo: Repo, patterns: [String], untrack: [String] = []) async {
        busy = true; defer { busy = false }
        let url = repo.url.appendingPathComponent(".gitignore")
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let have = Set(text.split(separator: "\n").map(String.init))
        let add = patterns.filter { !have.contains($0) }
        if !add.isEmpty {
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += add.joined(separator: "\n") + "\n"
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { setError("Could not write .gitignore: \(error.localizedDescription)"); return }
        }
        if !untrack.isEmpty {
            let r = await Git.run(["rm", "--cached", "-r", "-q", "--ignore-unmatch", "--"] + untrack, in: repo.url)
            if !r.ok { setError(r.text); await reload(repo); return }
        }
        setInfo(add.isEmpty ? "Already in .gitignore." : "Added \(add.joined(separator: ", ")) to .gitignore.")
        await reload(repo)
    }

    /// Tracked files an ignore choice would have to untrack: the file, the whole folder, or every file with that extension.
    func trackedFor(_ repo: Repo, _ c: Change, _ scope: IgnoreScope) async -> [String] {
        guard !c.untracked else { return [] }
        switch scope {
        case .file: return [c.path]
        case .folder:
            let d = (c.path as NSString).deletingLastPathComponent
            return d.isEmpty ? [] : [d]
        case .ext:
            let e = (c.path as NSString).pathExtension
            let r = await Git.run(["ls-files", "--", ":(glob)**/*." + e, "*." + e], in: repo.url)
            return r.out.split(separator: "\n").map(String.init)
        }
    }

    /// Moves a repo's folder to the Trash and forgets it everywhere. The remote copy is not touched.
    func deleteRepo(_ repo: Repo) async {
        busy = true; defer { busy = false }
        do { try FileManager.default.trashItem(at: repo.url, resultingItemURL: nil) }
        catch { setError("Could not move \(repo.name) to the Trash: \(error.localizedDescription)"); return }
        extraRepos.removeAll { $0 == repo.id }
        for i in workspaces.indices { workspaces[i].repos.removeAll { $0 == repo.id } }
        statuses[repo.id] = nil; side[repo.id] = nil; ticked[repo.id] = nil; messages[repo.id] = nil
        allRepos.removeAll { $0.id == repo.id }
        fixSelection()
        setInfo("Moved \(repo.name) to the Trash.")
    }

    /// The GitHub "owner/name" of a repo's origin remote, or nil when it has none or it is not on GitHub.
    func githubSlug(_ repo: Repo) async -> String? {
        let r = await Git.run(["remote", "get-url", "origin"], in: repo.url)
        return r.ok ? GitHubRemote.slug(from: r.out) : nil
    }

    /// Permanently deletes the repo on GitHub, then moves the local folder to the Trash. If GitHub refuses, nothing local is touched.
    func deleteRepoEverywhere(_ repo: Repo, slug: String) async {
        guard let gh = ghPath else { setError("The GitHub CLI (gh) is not installed."); return }
        busy = true
        let r = await Git.exec(gh, ["repo", "delete", slug, "--yes"], in: repo.url)
        busy = false
        guard r.ok else {
            let hint = r.text.lowercased().contains("delete_repo") ? "\n\nGitHub needs permission to delete repos. In Terminal run: gh auth refresh -s delete_repo" : ""
            setError("GitHub did not delete \(slug). The folder on this Mac was not touched.\n" + r.text + hint)
            return
        }
        await deleteRepo(repo)
        setInfo("Deleted \(slug) on GitHub and moved \(repo.name) to the Trash.")
    }

    // MARK: file tree
    static let treeLimit = 30_000

    /// The repo's files for the tree: tracked plus untracked that are not ignored (so .git and ignored folders stay out).
    func loadTree(_ repo: Repo) async {
        let r = await Git.run(["ls-files", "-z", "--cached", "--others", "--exclude-standard"], in: repo.url)
        guard r.ok else { return }
        var paths = Array(Set(r.out.split(separator: "\0").map(String.init)))
        if paths.count > Store.treeLimit { paths = Array(paths.prefix(Store.treeLimit)); treeTruncated.insert(repo.id) } else { treeTruncated.remove(repo.id) }
        let list = paths
        trees[repo.id] = await Task.detached { TreeBuilder.build(list) }.value
    }

    /// The start of a file for the preview pane: up to ~200 KB, with a note for binary files.
    func fileText(_ repo: Repo, _ path: String) async -> String {
        let u = repo.url.appendingPathComponent(path)
        guard let d = try? Data(contentsOf: u, options: .mappedIfSafe) else { return "This file is not on disk (it was deleted)." }
        if d.prefix(8000).contains(0) { return "Binary file. No text preview." }
        let lines = String(decoding: d.prefix(200_000), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        return lines.prefix(3000).joined(separator: "\n") + (d.count > 200_000 || lines.count > 3000 ? "\n… (shortened)" : "")
    }

    // MARK: editing
    /// A file's text for the editor: nil text and a reason when it cannot be edited as text here.
    func fileForEditing(_ repo: Repo, _ path: String) async -> (String?, String?) {
        let u = repo.url.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: u.path) else { return (nil, "This file is not on disk (it was deleted), so there is nothing to edit.") }
        let size = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
        if size > 1_000_000 { return (nil, "This file is larger than 1 MB. Open it in your own editor instead.") }
        guard let d = try? Data(contentsOf: u) else { return (nil, "Could not read this file.") }
        if d.prefix(8000).contains(0) { return (nil, "Binary file. It cannot be edited as text.") }
        guard let s = String(data: d, encoding: .utf8) else { return (nil, "This file is not UTF-8 text, so it is not edited here.") }
        return (s, nil)
    }

    /// Writes an edited file, then re-reads the repo so the changes list, counts and tree are current. Returns an error text or nil.
    func saveFile(_ repo: Repo, _ path: String, _ text: String) async -> String? {
        do { try text.write(to: repo.url.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        catch { return error.localizedDescription }
        await reload(repo)
        return nil
    }

    // MARK: clone
    /// The folder a clone would be made in, and whether it already exists.
    func cloneDestination(parent: String, folder: String) -> URL { URL(fileURLWithPath: parent).appendingPathComponent(folder) }

    /// Your repos on GitHub (needs gh, signed in), for the clone sheet's picker.
    func listGitHubRepos() async -> (items: [GitHubRepoItem], note: String?) {
        guard let gh = ghPath else { return ([], "Install the GitHub CLI (brew install gh) to pick from your GitHub repos.") }
        let r = await Git.exec(gh, ["repo", "list", "--json", "nameWithOwner,description,isPrivate", "--limit", "100"], in: URL(fileURLWithPath: NSHomeDirectory()))
        guard r.ok, let items = try? JSONDecoder().decode([GitHubRepoItem].self, from: Data(r.out.utf8)) else {
            return ([], r.text.lowercased().contains("auth") ? "Run gh auth login in Terminal to list your GitHub repos." : "Could not list your GitHub repos.")
        }
        return (items, items.isEmpty ? "No repos found on your GitHub account." : nil)
    }

    /// Clones `source` (a URL, or owner/name) into `parent/folder`, then adds it to the chosen workspaces. Returns an error text or nil.
    func cloneRepo(source: String, parent: String, folder: String, branch: String = "", workspaceIDs: [String], newWorkspace: String? = nil) async -> String? {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return "Enter the repository URL or owner/name." }
        guard !name.isEmpty, !name.contains("/") else { return "Enter a folder name without slashes." }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDir), isDir.boolValue else { return "The folder \(parent) does not exist." }
        let dest = cloneDestination(parent: parent, folder: name)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return "\(dest.path) already exists. Choose another folder name." }
        busy = true; defer { busy = false }
        let b = branch.trimmingCharacters(in: .whitespaces)
        let r: GitResult
        if CloneSource.isShorthand(src) {
            guard let gh = ghPath else { return "owner/name needs the GitHub CLI (gh). Install it, or paste the full URL." }
            r = await Git.exec(gh, ["repo", "clone", src, dest.path] + (b.isEmpty ? [] : ["--", "--branch", b]), in: URL(fileURLWithPath: parent))
        } else {
            r = await Git.run(["clone"] + (b.isEmpty ? [] : ["--branch", b]) + ["--", src, dest.path], in: URL(fileURLWithPath: parent))
        }
        guard r.ok else {
            try? FileManager.default.removeItem(at: dest)   // a failed clone can leave a half-made folder; it is ours, so remove it
            return r.text
        }
        if !roots.contains(parent) && !extraRepos.contains(dest.path) { extraRepos.append(dest.path) }
        var ids = workspaceIDs
        if let n = newWorkspace?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            let w = Workspace(name: n); workspaces.append(w); ids.append(w.id)
        }
        for id in ids { if let i = workspaces.firstIndex(where: { $0.id == id }), !workspaces[i].repos.contains(dest.path) { workspaces[i].repos.append(dest.path) } }
        await scan()
        if let cw = currentWorkspace, !cw.repos.contains(dest.path) { current = nil }
        selected = dest.path
        setInfo("Cloned \(name) into \(parent).")
        return nil
    }

    // MARK: pull requests (GitHub CLI)
    var ghPath: String? { ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) } }

    func loadPR(_ repo: Repo, _ number: Int) async -> (PRDetail?, [String: String], String?) {
        guard let gh = ghPath else { return (nil, [:], "The GitHub CLI (gh) is not installed.") }
        let v = await Git.exec(gh, ["pr", "view", String(number), "--json", PRDetail.fields], in: repo.url)
        guard v.ok, let d = try? JSONDecoder().decode(PRDetail.self, from: Data(v.out.utf8)) else { return (nil, [:], v.ok ? "Could not read the pull request." : v.text) }
        let df = await Git.exec(gh, ["pr", "diff", String(number), "--color", "never"], in: repo.url)
        return (d, df.ok ? PRParser.splitDiff(df.out) : [:], df.ok ? nil : df.text)
    }

    enum Review { case approve, requestChanges, comment }
    /// Posts a comment or a review. Returns the error text, or nil on success.
    func review(_ repo: Repo, _ number: Int, _ kind: Review, _ body: String) async -> String? {
        guard let gh = ghPath else { return "The GitHub CLI (gh) is not installed." }
        var args = ["pr", "review", String(number)]
        switch kind {
        case .approve: args.append("--approve")
        case .requestChanges: args.append("--request-changes")
        case .comment: args.append("--comment")
        }
        if !body.isEmpty { args += ["--body", body] }
        let r = await Git.exec(gh, args, in: repo.url)
        return r.ok ? nil : r.text
    }
    func comment(_ repo: Repo, _ number: Int, _ body: String) async -> String? {
        guard let gh = ghPath else { return "The GitHub CLI (gh) is not installed." }
        let r = await Git.exec(gh, ["pr", "comment", String(number), "--body", body], in: repo.url)
        return r.ok ? nil : r.text
    }
    /// GitHub has no way to delete a pull request, so this closes it (and can delete its branch).
    func closePR(_ repo: Repo, _ number: Int, deleteBranch: Bool) async -> String? {
        guard let gh = ghPath else { return "The GitHub CLI (gh) is not installed." }
        let r = await Git.exec(gh, ["pr", "close", String(number)] + (deleteBranch ? ["--delete-branch"] : []), in: repo.url)
        await reload(repo)
        return r.ok ? nil : r.text
    }

    private func lastLine(_ s: String) -> String { s.split(separator: "\n").last.map(String.init) ?? s }
    func setError(_ t: String) { banner = Banner(text: t, isError: true) }
    func setInfo(_ t: String) { banner = Banner(text: t, isError: false) }
}
