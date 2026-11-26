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
    @Published var busy = false
    @Published var scanning = false
    private var seen: [String: Set<String>] = [:]

    init() {
        let d = UserDefaults.standard
        var r = d.stringArray(forKey: "roots") ?? []
        if r.isEmpty { r = [d.string(forKey: "workspace") ?? (NSHomeDirectory() + "/Desktop/repos")] }
        roots = r
        extraRepos = d.stringArray(forKey: "extraRepos") ?? []
        workspaces = (d.data(forKey: "workspaces").flatMap { try? JSONDecoder().decode([Workspace].self, from: $0) }) ?? []
        current = d.string(forKey: "current")
    }

    private func save() {
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
        scanning = false
    }

    /// 02-repo: status, then line counts.
    func refresh(_ repo: Repo, fetch: Bool = false) async {
        if fetch { _ = await Git.run(["fetch", "--quiet", "--prune"], in: repo.url) }
        let r = await Git.run(["status", "--porcelain=v2", "--branch", "--untracked-files=all", "-z"], in: repo.url)
        guard r.ok else { setError("\(repo.name): \(r.text)"); return }
        var st = StatusParser.parse(r.out)
        let ns = await Git.run(["diff", "HEAD", "--numstat"], in: repo.url)
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
        let b = await Git.run(["for-each-ref", "--format=%(HEAD)%09%(refname)%09%(refname:short)%09%(upstream:track)", "refs/heads", "refs/remotes"], in: repo.url)
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

    func switchBranch(_ repo: Repo, _ b: BranchInfo) async {
        busy = true; defer { busy = false }
        let r = await Git.run(["switch", b.switchName], in: repo.url)
        r.ok ? setInfo("Switched to \(b.switchName).") : setError(r.text)
        await refresh(repo); await loadSide(repo)
    }

    func checkoutPR(_ repo: Repo, _ pr: PullRequest) async {
        guard let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        busy = true; defer { busy = false }
        let r = await Git.exec(gh, ["pr", "checkout", String(pr.number)], in: repo.url)
        r.ok ? setInfo("Checked out #\(pr.number).") : setError(r.text)
        await refresh(repo); await loadSide(repo)
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
        await refresh(repo); await loadSide(repo)
    }

    func pull(_ repo: Repo) async {
        busy = true; defer { busy = false }
        let r = await Git.run(["pull", "--ff-only"], in: repo.url)
        r.ok ? setInfo(r.text.isEmpty ? "Pulled." : lastLine(r.text)) : setError(r.text)
        await refresh(repo); await loadSide(repo)
    }

    func push(_ repo: Repo) async {
        busy = true; defer { busy = false }
        let st = statuses[repo.id]
        var args = ["push"]
        if st?.upstream == nil, let b = st?.branch, !b.isEmpty { args = ["push", "-u", "origin", b] }
        let r = await Git.run(args, in: repo.url)
        r.ok ? setInfo("Pushed.") : setError(r.text)
        await refresh(repo); await loadSide(repo)
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
        await refresh(repo); await loadSide(repo)
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
            if !r.ok { setError(r.text); await refresh(repo); return }
        }
        setInfo(add.isEmpty ? "Already in .gitignore." : "Added \(add.joined(separator: ", ")) to .gitignore.")
        await refresh(repo)
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
        await loadSide(repo)
        return r.ok ? nil : r.text
    }

    private func lastLine(_ s: String) -> String { s.split(separator: "\n").last.map(String.init) ?? s }
    func setError(_ t: String) { banner = Banner(text: t, isError: true) }
    func setInfo(_ t: String) { banner = Banner(text: t, isError: false) }
}
