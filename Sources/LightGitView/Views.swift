import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var showSide = true
    @State private var showRoots = false
    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let repo = store.selectedRepo {
                RepoDetail(repo: repo).id(repo.id)
                    .inspector(isPresented: $showSide) { SidePanel(repo: repo).id(repo.id).inspectorColumnWidth(min: 260, ideal: 300, max: 380) }
            }
            else { EmptyState() }
        }
        .sheet(isPresented: $showRoots) { RootsSheet() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button("Add repo or repos folder…") { store.addPath() }
                    Button("Manage repos folders…") { showRoots = true }
                } label: { Label("Add repos", systemImage: "plus") }
                .help("Add a repo, or the folder that holds your repos")
            }
            ToolbarItem {
                Button { showSide.toggle() } label: { Label("Branches and pull requests", systemImage: "sidebar.trailing") }
                    .help("Show or hide branches, remote changes and pull requests")
            }
            ToolbarItem {
                Button { Task { await store.scan() } } label: { Label("Refresh all", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }
                    .help("Rescan the repos folders and refresh every repo (fetches from the remote)")
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

struct EmptyState: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 10) {
            Text(store.currentWorkspace == nil ? "No repos found" : "No repos in \(store.currentName)").font(.title3.weight(.semibold))
            Text(store.currentWorkspace == nil ? (store.roots.joined(separator: "\n")) : "Right-click a repo in All repos and choose Add to workspace.").foregroundStyle(.secondary).textSelection(.enabled).multilineTextAlignment(.center)
            Button("Add repo or repos folder…") { store.addPath() }.buttonStyle(.borderedProminent)
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @State private var showRoots = false
    @State private var showWorkspaces = false
    var body: some View {
        VStack(spacing: 0) {
            workspaceMenu.padding(.horizontal, 12).padding(.vertical, 8)
            List(selection: $store.selected) {
                Section("\(store.repos.count) repo\(store.repos.count == 1 ? "" : "s")") {
                    ForEach(store.repos) { r in
                        SidebarRow(repo: r, st: store.statuses[r.id]).tag(r.id)
                            .contextMenu { repoMenu(r) }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay { if store.repos.isEmpty && !store.scanning { Text(store.currentWorkspace == nil ? "No repos found" : "No repos in this workspace").foregroundStyle(.secondary) } }
        }
        .onChange(of: store.selected) { _, new in
            if let r = store.selectedRepo, new != nil { Task { await store.refresh(r, fetch: true) } }
        }
        .sheet(isPresented: $showRoots) { RootsSheet() }
        .sheet(isPresented: $showWorkspaces) { WorkspacesSheet() }
    }

    var workspaceMenu: some View {
        Menu {
            Button { store.current = nil } label: { Label("All repos (\(store.count(in: nil)))", systemImage: store.current == nil ? "checkmark" : "tray.full") }
            if !store.workspaces.isEmpty { Divider() }
            ForEach(store.workspaces) { w in
                Button { store.current = w.id } label: { Label("\(w.name) (\(store.count(in: w)))", systemImage: store.current == w.id ? "checkmark" : "folder") }
            }
            Divider()
            Button("New workspace…") { if let n = promptText("New workspace", "Name, for example Work", "") { store.newWorkspace(named: n) } }
            Button("Manage workspaces…") { showWorkspaces = true }
            if let w = store.currentWorkspace {
                Button("Rename “\(w.name)”…") { if let n = promptText("Rename workspace", "New name", w.name) { store.rename(w, to: n) } }
                Button("Delete “\(w.name)”…", role: .destructive) {
                    if confirm("Delete workspace “\(w.name)”?", "Only the group is deleted. The repos stay on disk and in All repos.", button: "Delete") { store.delete(w) }
                }
            }
            Divider()
            Button("Add repo or repos folder…") { store.addPath() }
            Button("Manage repos folders…") { showRoots = true }
        } label: {
            HStack {
                Image(systemName: store.currentWorkspace == nil ? "tray.full" : "folder")
                Text(store.currentName).fontWeight(.semibold).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help("Switch workspace")
    }

    @ViewBuilder func repoMenu(_ r: Repo) -> some View {
        if !store.workspaces.isEmpty {
            Menu("Workspaces") {
                ForEach(store.workspaces) { w in
                    Button { store.toggleMember(r, w) } label: { Label(w.name, systemImage: store.isIn(r, w) ? "checkmark" : "") }
                }
            }
        }
        Button("New workspace with this repo…") {
            if let n = promptText("New workspace", "Name, for example Work", "") { store.newWorkspace(named: n); if let w = store.currentWorkspace { store.toggleMember(r, w) } }
        }
        if let w = store.currentWorkspace, store.isIn(r, w) {
            Button("Remove from “\(w.name)”") { store.toggleMember(r, w) }
        }
        Divider()
        Button("Delete from disk…", role: .destructive) { askDeleteRepo(r) }
        Button("Delete from disk and GitHub…", role: .destructive) { askDeleteEverywhere(r) }
    }

    /// The most destructive act in the app: removes the repo on GitHub for good. Asks for the repo's name to be typed.
    func askDeleteEverywhere(_ r: Repo) {
        Task {
            guard let slug = await store.githubSlug(r) else {
                _ = confirm("No GitHub repo to delete", "\(r.name) has no origin remote on github.com. Use Delete from disk instead.", button: "OK"); return
            }
            let st = store.statuses[r.id]
            var local = ""
            if let st, !st.changes.isEmpty || st.ahead > 0 { local = "\n\nThis Mac also holds \(st.changes.count) uncommitted change\(st.changes.count == 1 ? "" : "s") and \(st.ahead) unpushed commit\(st.ahead == 1 ? "" : "s")." }
            let typed = promptText("Delete \(slug) on GitHub and on this Mac?",
                "This permanently deletes \(slug) on GitHub, with its issues, pull requests, releases and stars. It cannot be undone, and private forks may be deleted with it. The folder on this Mac is moved to the Trash afterwards, and will then be the only copy." + local + "\n\nType \(slug) to confirm.", "")
            guard let typed else { return }
            guard typed.trimmingCharacters(in: .whitespaces) == slug else {
                _ = confirm("Name did not match", "Nothing was deleted.", button: "OK"); return
            }
            await store.deleteRepoEverywhere(r, slug: slug)
        }
    }

    func askDeleteRepo(_ r: Repo) {
        let st = store.statuses[r.id]
        var risk = ""
        if let st {
            var parts: [String] = []
            if !st.changes.isEmpty { parts.append("\(st.changes.count) uncommitted change\(st.changes.count == 1 ? "" : "s")") }
            if st.ahead > 0 { parts.append("\(st.ahead) commit\(st.ahead == 1 ? "" : "s") not pushed") }
            if !parts.isEmpty { risk = "\n\nThis repo has " + parts.joined(separator: " and ") + " that exist only on this Mac." }
        }
        if confirm("Move “\(r.name)” to the Trash?", "The folder \(r.url.path) is moved to the Trash, so you can still put it back. The copy on the remote is not touched." + risk, button: "Move to Trash") {
            Task { await store.deleteRepo(r) }
        }
    }
}

struct WorkspacesSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspaces").font(.title3.weight(.semibold))
            Text("Group repos, for example Work or Personal. Deleting a workspace never deletes repos.").foregroundStyle(.secondary)
            List {
                ForEach(store.workspaces) { w in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(w.name).lineLimit(1)
                        Text("\(store.count(in: w)) repos").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Rename…") { if let n = promptText("Rename workspace", "New name", w.name) { store.rename(w, to: n) } }
                        Button("Delete…", role: .destructive) {
                            if confirm("Delete workspace “\(w.name)”?", "Only the group is deleted. The repos stay on disk and in All repos.", button: "Delete") { store.delete(w) }
                        }
                    }
                }
                if store.workspaces.isEmpty { Text("No workspaces yet").foregroundStyle(.secondary) }
            }.frame(minHeight: 160)
            HStack {
                Button("New workspace…") { if let n = promptText("New workspace", "Name, for example Work", "") { store.newWorkspace(named: n) } }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 520)
    }
}

struct RootsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repos folders").font(.title3.weight(.semibold))
            Text("Every repo directly inside these folders appears in All repos.").foregroundStyle(.secondary)
            List {
                ForEach(store.roots, id: \.self) { r in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(r).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button("Change…") { store.changeRoot(r) }
                        Button("Remove") { store.removeRoot(r) }
                    }
                }
                if store.roots.isEmpty { Text("No folders yet").foregroundStyle(.secondary) }
            }.frame(minHeight: 140)
            HStack {
                Button("Add folder…") { store.addPath() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 520)
    }
}

@MainActor
func promptText(_ title: String, _ message: String, _ value: String) -> String? {
    let a = NSAlert()
    a.messageText = title; a.informativeText = message
    let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); f.stringValue = value
    a.accessoryView = f
    a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
    a.window.initialFirstResponder = f
    return a.runModal() == .alertFirstButtonReturn ? f.stringValue : nil
}

struct SidebarRow: View {
    let repo: Repo
    let st: RepoStatus?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(repo.name).lineLimit(1)
            if let st {
                Text(st.branch).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    if st.changes.isEmpty && st.ahead == 0 && st.behind == 0 {
                        Text("up to date").foregroundStyle(.secondary)
                    }
                    if !st.changes.isEmpty { Text("\(st.changes.count) local").foregroundStyle(Color.brand).help("Changed files not committed yet") }
                    if st.ahead > 0 { Text("↑\(st.ahead) push").help("Commits to push") }
                    if st.behind > 0 { Text("↓\(st.behind) pull").fontWeight(.semibold).help("Commits on the remote to pull") }
                }.font(.caption)
            }
        }.padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct SidePanel: View {
    @EnvironmentObject var store: Store
    let repo: Repo
    @State private var reviewing: PullRequest?
    var info: SideInfo { store.side[repo.id] ?? SideInfo() }
    var st: RepoStatus { store.statuses[repo.id] ?? RepoStatus() }
    var body: some View {
        List {
            Section("Remote changes not in local (\(info.incoming.count))") {
                if st.upstream == nil { Text("No upstream branch").foregroundStyle(.secondary) }
                else if info.incoming.isEmpty { Text("Nothing to pull").foregroundStyle(.secondary) }
                ForEach(info.incoming) { commitRow($0) }
            }
            Section("Local commits not pushed (\(info.outgoing.count))") {
                if info.outgoing.isEmpty { Text("Nothing to push").foregroundStyle(.secondary) }
                ForEach(info.outgoing) { commitRow($0) }
            }
            Section("Branches") {
                ForEach(info.branches) { b in
                    Button { if !b.isCurrent { Task { await store.switchBranch(repo, b) } } } label: {
                        HStack {
                            Image(systemName: b.isCurrent ? "checkmark" : (b.isRemote ? "cloud" : "arrow.triangle.branch")).frame(width: 14)
                                .foregroundStyle(b.isCurrent ? Color.brand : Color.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.name).lineLimit(1).truncationMode(.middle).fontWeight(b.isCurrent ? .semibold : .regular)
                                if !b.track.isEmpty { Text(b.track).font(.caption).foregroundStyle(.secondary) }
                                if b.isRemote { Text("on remote, not local").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(store.busy)
                    .help(b.isCurrent ? "Current branch" : "Switch to \(b.switchName)")
                    .accessibilityLabel(b.isCurrent ? "\(b.name), current branch" : "Switch to \(b.name)")
                }
            }
            Section("Pull requests (\(info.prs.count))") {
                if let n = info.prNote { Text(n).foregroundStyle(.secondary) }
                ForEach(info.prs) { pr in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("#\(pr.number) \(pr.title)").lineLimit(2)
                        Text("\(pr.headRefName) · \(pr.author.login)\(pr.isDraft ? " · draft" : "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        HStack {
                            Button("Review…") { reviewing = pr }
                            Button("Open") { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } }
                            Button("Check out") { Task { await store.checkoutPR(repo, pr) } }.disabled(store.busy)
                        }.controlSize(.small)
                    }.padding(.vertical, 2)
                }
            }
        }
        .font(.callout)
        .task { await store.loadSide(repo) }
        .sheet(item: $reviewing) { pr in PRSheet(repo: repo, number: pr.number).environmentObject(store) }
    }
    func commitRow(_ c: CommitInfo) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(c.subject).lineLimit(2)
            Text("\(c.hash) · \(c.author) · \(c.when)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.padding(.vertical, 1)
    }
}

@MainActor
func confirm(_ title: String, _ message: String, button: String) -> Bool {
    let a = NSAlert()
    a.messageText = title; a.informativeText = message; a.alertStyle = .warning
    a.addButton(withTitle: button); a.addButton(withTitle: "Cancel")
    return a.runModal() == .alertFirstButtonReturn
}

struct RepoDetail: View {
    @EnvironmentObject var store: Store
    let repo: Repo
    @State private var focus: Change?
    @State private var diffText = ""
        @State private var collapsed = Set<String>()

    var st: RepoStatus { store.statuses[repo.id] ?? RepoStatus() }
    var ticked: Set<String> { store.ticked[repo.id] ?? [] }
    var message: Binding<String> { Binding(get: { store.messages[repo.id] ?? "" }, set: { store.messages[repo.id] = $0 }) }
    var canCommit: Bool { !message.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ticked.isEmpty && !store.busy }
    var secretsTicked: [Change] { st.changes.filter { $0.isSecret && ticked.contains($0.path) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                changesList.frame(minWidth: 240, idealWidth: 320)
                diffPane.frame(minWidth: 240)
            }
            Divider()
            commitBox
        }
        .task { await store.refresh(repo, fetch: true) }
        .onChange(of: st.changes.map(\.path)) { _, paths in
            if let f = focus, !paths.contains(f.path) { focus = nil; diffText = "" }
            else if let f = focus { focus = st.changes.first { $0.path == f.path } ?? f; Task { await loadDiff() } }
        }
    }

    var workspaceTags: some View {
        HStack(spacing: 6) {
            ForEach(store.workspaces.filter { store.isIn(repo, $0) }) { w in
                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.caption2)
                    Text(w.name).font(.caption)
                    Button { store.toggleMember(repo, w) } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                        .buttonStyle(.borderless).help("Remove this repo from \(w.name)").accessibilityLabel("Remove from \(w.name)")
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color.brand.opacity(0.15)))
            }
            Menu {
                ForEach(store.workspaces.filter { !store.isIn(repo, $0) }) { w in
                    Button(w.name) { store.toggleMember(repo, w) }
                }
                Button("New workspace…") {
                    if let n = promptText("New workspace", "Name, for example Work", "") {
                        let prev = store.current; store.newWorkspace(named: n)
                        if let w = store.currentWorkspace { store.toggleMember(repo, w) }
                        store.current = prev
                    }
                }
            } label: { Label("Workspace", systemImage: "plus").font(.caption) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Add this repo to a workspace")
            if !store.workspaces.contains(where: { store.isIn(repo, $0) }) { Text("not in a workspace").font(.caption).foregroundStyle(.secondary) }
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name).font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    Text(st.branch.isEmpty ? "…" : st.branch)
                    if let u = st.upstream { Text("→ \(u)").foregroundStyle(.secondary) } else { Text("no upstream").foregroundStyle(.secondary) }
                    if st.ahead > 0 { Text("↑\(st.ahead) ahead") }
                    if st.behind > 0 { Text("↓\(st.behind) behind").foregroundStyle(Color.brand) }
                }.font(.callout)
                workspaceTags
            }
            Spacer()
            if store.busy { ProgressView().controlSize(.small) }
            Button { Task { await store.refresh(repo, fetch: true); await store.loadSide(repo); await loadDiff() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(store.busy).keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Fetch from the remote and update this repo's files, branches and pull requests")
            Button { Task { await store.pull(repo) } } label: { Label("Pull", systemImage: "arrow.down") }
                .disabled(store.busy || st.upstream == nil || st.behind == 0)
                .help(st.behind == 0 ? "Nothing to pull" : "Pull, fast-forward only")
            Button { Task { await store.push(repo) } } label: { Label("Push", systemImage: "arrow.up") }
                .disabled(store.busy || st.behind > 0 || (st.ahead == 0 && st.upstream != nil))
                .help(st.behind > 0 ? "Pull first: the remote has newer commits" : (st.ahead == 0 && st.upstream != nil ? "Nothing to push" : "Push"))
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    struct Row: Identifiable {
        let id: String; let depth: Int; let name: String
        let change: Change?; let files: [String]   // files: every file path under a folder row
        var isDir: Bool { change == nil }
    }

    var rows: [Row] {
        var out: [Row] = []
        var emitted = Set<String>()
        for c in st.changes.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            let parts = c.path.split(separator: "/").map(String.init)
            var hidden = false
            for i in 0..<max(parts.count - 1, 0) {
                let dir = parts[0...i].joined(separator: "/")
                if !emitted.contains(dir) { emitted.insert(dir); out.append(dirRow(dir, i)) }
                if collapsed.contains(dir) { hidden = true; break }
            }
            if !hidden { out.append(Row(id: c.path, depth: parts.count - 1, name: parts.last ?? c.path, change: c, files: [c.path])) }
        }
        return out
    }
    func dirRow(_ dir: String, _ depth: Int) -> Row {
        let files = st.changes.map(\.path).filter { $0.hasPrefix(dir + "/") }
        return Row(id: "dir:" + dir, depth: depth, name: (dir as NSString).lastPathComponent, change: nil, files: files)
    }
    func dirOf(_ r: Row) -> String { String(r.id.dropFirst(4)) }

    /// Ignore menu and Discard button for a file row, or Ignore and Discard for a folder row.
    func rowActions(_ files: [String], _ cs: [Change], dir: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let dir {
                Button { askIgnoreFolder(dir, cs) } label: { Image(systemName: "eye.slash").frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .help("Ignore this folder: add it to .gitignore").accessibilityLabel("Ignore folder")
            } else if let c = cs.first {
                Menu { ignoreMenu(c) } label: { Image(systemName: "eye.slash").frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Ignore: add to .gitignore").accessibilityLabel("Ignore")
            }
            Button { askDiscard(cs) } label: { Image(systemName: "trash").frame(width: 22, height: 22).contentShape(Rectangle()) }
                .help("Discard: remove this change").accessibilityLabel("Discard")
        }.buttonStyle(.borderless).foregroundStyle(.secondary)
    }

    @ViewBuilder func ignoreMenu(_ c: Change) -> some View {
        ForEach(IgnoreScope.allCases, id: \.self) { scope in
            if let label = scope.label(for: c.path) { Button(label) { askIgnore(c, scope) } }
        }
    }

    /// Adds the chosen pattern to .gitignore. A file git already tracks must also leave the index, which needs a yes.
    func askIgnore(_ c: Change, _ scope: IgnoreScope) {
        guard let pat = scope.pattern(for: c.path) else { return }
        Task {
            let tracked = await store.trackedFor(repo, c, scope)
            if !tracked.isEmpty {
                let what = tracked.count == 1 ? tracked[0] : "\(tracked.count) files"
                guard confirm("Stop tracking \(what) and ignore it?", "\(pat) is added to .gitignore and the file is taken out of git's index. It stays on your disk. Commit the removal to take it out of the repo.", button: "Ignore and stop tracking") else { return }
            }
            await store.ignore(repo, patterns: [pat], untrack: tracked)
        }
    }
    func askIgnoreFolder(_ dir: String, _ cs: [Change]) {
        let hasTracked = cs.contains { !$0.untracked }
        if hasTracked && !confirm("Stop tracking files in \(dir)/ and ignore the folder?", "/\(dir)/ is added to .gitignore and the tracked files inside are taken out of git's index. They stay on your disk. Commit the removal to take them out of the repo.", button: "Ignore and stop tracking") { return }
        Task { await store.ignore(repo, patterns: ["/" + dir + "/"], untrack: hasTracked ? [dir] : []) }
    }

    func askDiscard(_ cs: [Change]) {
        guard !cs.isEmpty else { return }
        let what = cs.count == 1 ? cs[0].path : "\(cs.count) files"
        if confirm("Discard \(what)?", "Changes are removed (tracked files go back to the last commit; new files and folders are moved to the Trash).", button: "Discard") {
            Task { await store.discard(repo, cs) }
        }
    }

    var changesList: some View {
        Group {
            if st.changes.isEmpty {
                VStack(spacing: 4) {
                    Text("Clean").font(.headline)
                    Text("No changes in this repo").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { focus?.id }, set: { id in focus = st.changes.first { $0.id == id }; Task { await loadDiff() } })) {
                    ForEach(rows) { r in
                        if let c = r.change {
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(get: { ticked.contains(c.path) }, set: { _ in store.toggle(repo, c.path) }))
                                    .labelsHidden().toggleStyle(.checkbox)
                                    .accessibilityLabel("Include \(c.path) in the commit")
                                Text(c.code).font(.callout.weight(.bold)).frame(width: 16)
                                    .foregroundStyle(c.code == "D" ? Color.red : (c.untracked ? Color.secondary : Color.primary))
                                Text(r.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                if c.isSecret { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange).help("Looks like a secret").accessibilityLabel("Looks like a secret") }
                                if let a = c.added, let d = c.deleted, !c.untracked {
                                    Text("+\(a)").foregroundStyle(.green); Text("−\(d)").foregroundStyle(.red)
                                }
                                rowActions(r.files, [c])
                            }
                            .font(.callout).padding(.leading, CGFloat(r.depth) * 16).tag(c.id)
                            .contextMenu {
                                Button("Discard…", role: .destructive) { askDiscard([c]) }
                                Divider()
                                ignoreMenu(c)
                            }
                        } else {
                            let on = r.files.filter { ticked.contains($0) }.count
                            let isOpen = !collapsed.contains(dirOf(r))
                            HStack(spacing: 8) {
                                Button { if isOpen { collapsed.insert(dirOf(r)) } else { collapsed.remove(dirOf(r)) } } label: {
                                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").frame(width: 12)
                                }.buttonStyle(.plain).accessibilityLabel(isOpen ? "Collapse \(r.name)" : "Expand \(r.name)")
                                Button { store.setTicked(repo, r.files, on: on != r.files.count) } label: {
                                    Image(systemName: on == 0 ? "square" : (on == r.files.count ? "checkmark.square.fill" : "minus.square.fill"))
                                        .foregroundStyle(on == 0 ? Color.secondary : Color.brand)
                                }.buttonStyle(.plain)
                                .accessibilityLabel("Include all \(r.files.count) files in \(r.name)")
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                Text(r.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(on)/\(r.files.count)").font(.caption).foregroundStyle(.secondary)
                                rowActions(r.files, st.changes.filter { r.files.contains($0.path) }, dir: dirOf(r))
                            }
                            .font(.callout).padding(.leading, CGFloat(r.depth) * 16)
                            .selectionDisabled()
                        }
                    }
                }
            }
        }
    }

    var diffPane: some View {
        Group {
            if focus == nil { Text("Select a file to see its changes").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                DiffView(text: diffText)
            }
        }
    }

    var commitBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let b = store.banner {
                HStack(alignment: .top) {
                    Image(systemName: b.isError ? "xmark.octagon.fill" : "checkmark.circle.fill").foregroundStyle(b.isError ? Color.red : Color.green)
                    Text(b.text).textSelection(.enabled).font(.callout)
                    Spacer()
                    Button { store.banner = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Commit message", text: message, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button("Commit \(ticked.count)") {
                    if secretsTicked.isEmpty || confirm("Commit a file that may hold secrets?", secretsTicked.map(\.path).joined(separator: ", "), button: "Commit anyway") { Task { await store.commit(repo) } }
                }
                .buttonStyle(.borderedProminent).disabled(!canCommit)
                .help(message.wrappedValue.isEmpty ? "Type a message first" : (ticked.isEmpty ? "Tick at least one file" : "Commit ticked files"))
            }
        }.padding(16)
    }

    func loadDiff() async {
        guard let c = focus else { return }
        diffText = await store.diff(repo, c)
    }
}


/// A patch drawn line by line: additions green, deletions red, hunk headers in the accent colour.
struct DiffView: View {
    let text: String
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, l in
                    Text(l.isEmpty ? " " : String(l))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(l.hasPrefix("+") && !l.hasPrefix("+++") ? Color.green : (l.hasPrefix("-") && !l.hasPrefix("---") ? Color.red : (l.hasPrefix("@@") ? Color.brand : Color.primary)))
                        .textSelection(.enabled)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Open a pull request: read its files and diff and its conversation, then comment, approve, request changes or close it.
struct PRSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let repo: Repo
    let number: Int
    @State private var pr: PRDetail?
    @State private var diffs: [String: String] = [:]
    @State private var loadError: String?
    @State private var tab = 0
    @State private var file: String?
    @State private var text = ""
    @State private var working = false
    @State private var result: Banner?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let pr {
                Picker("", selection: $tab) {
                    Text("Files changed (\(pr.files.count))").tag(0)
                    Text("Conversation (\(pr.comments.count + pr.reviews.count))").tag(1)
                }.pickerStyle(.segmented).labelsHidden().padding(10)
                Divider()
                if tab == 0 { filesTab(pr) } else { conversationTab(pr) }
                Divider()
                actionBar(pr)
            } else {
                VStack(spacing: 8) {
                    if let e = loadError { Text("Could not load this pull request").font(.headline); Text(e).foregroundStyle(.secondary).textSelection(.enabled) }
                    else { ProgressView(); Text("Loading pull request…").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 940, minHeight: 640)
        .task { await load() }
    }

    func load() async {
        let (d, df, err) = await store.loadPR(repo, number)
        pr = d; diffs = df; loadError = d == nil ? err : nil
        if file == nil { file = d?.files.first?.path }
    }

    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.map { "#\($0.number) \($0.title)" } ?? "Pull request #\(number)").font(.title3.weight(.semibold)).lineLimit(2)
                if let pr {
                    HStack(spacing: 8) {
                        Text(pr.state + (pr.isDraft ? " · draft" : "")).fontWeight(.semibold).foregroundStyle(pr.isOpen ? Color.green : Color.secondary)
                        Text("\(pr.author?.login ?? "unknown") wants to merge \(pr.headRefName) into \(pr.baseRefName)").foregroundStyle(.secondary)
                        Text("+\(pr.additions)").foregroundStyle(.green); Text("−\(pr.deletions)").foregroundStyle(.red)
                        if let d = pr.reviewDecision, !d.isEmpty { Text(d.replacingOccurrences(of: "_", with: " ").lowercased()).padding(.horizontal, 6).background(Capsule().fill(Color.brand.opacity(0.15))) }
                    }.font(.callout)
                }
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(16)
    }

    func filesTab(_ pr: PRDetail) -> some View {
        HSplitView {
            List(pr.files, selection: $file) { f in
                HStack {
                    Text(f.path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("+\(f.additions)").foregroundStyle(.green); Text("−\(f.deletions)").foregroundStyle(.red)
                }.font(.callout).tag(f.path)
            }.frame(minWidth: 260, idealWidth: 320)
            Group {
                if let f = file, let d = diffs[f] { DiffView(text: d) }
                else { Text(diffs.isEmpty ? "No diff available" : "Select a file to see its changes").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.frame(minWidth: 320)
        }
    }

    func conversationTab(_ pr: PRDetail) -> some View {
        struct Item: Identifiable { let id: String; let who: String; let when: String; let kind: String; let body: String }
        var items = pr.comments.map { Item(id: "c" + $0.id, who: $0.author?.login ?? "unknown", when: $0.createdAt ?? "", kind: "commented", body: $0.body) }
        items += pr.reviews.map { Item(id: "r" + $0.id, who: $0.author?.login ?? "unknown", when: $0.submittedAt ?? "", kind: $0.state.replacingOccurrences(of: "_", with: " ").lowercased(), body: $0.body) }
        items.sort { $0.when < $1.when }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(pr.body.isEmpty ? "No description." : pr.body).textSelection(.enabled).foregroundStyle(pr.body.isEmpty ? .secondary : .primary)
                Divider()
                if items.isEmpty { Text("No comments or reviews yet.").foregroundStyle(.secondary) }
                ForEach(items) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(i.who).fontWeight(.semibold); Text(i.kind).foregroundStyle(.secondary); Spacer(); Text(String(i.when.prefix(10))).font(.caption).foregroundStyle(.secondary) }
                        if !i.body.isEmpty { Text(i.body).textSelection(.enabled) }
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func actionBar(_ pr: PRDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = result {
                HStack(alignment: .top) {
                    Image(systemName: r.isError ? "xmark.octagon.fill" : "checkmark.circle.fill").foregroundStyle(r.isError ? Color.red : Color.green)
                    Text(r.text).textSelection(.enabled).font(.callout)
                }
            }
            if pr.isOpen {
                TextField("Write a comment or review message", text: $text, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Comment") { run("Comment posted.", reload: true) { await store.comment(repo, number, text.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                        .disabled(blank || working)
                    Button("Approve") {
                        if confirm("Approve #\(number)?", "Your approval is posted on GitHub for everyone to see.", button: "Approve") {
                            run("Approved.", reload: true) { await store.review(repo, number, .approve, text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                    }.buttonStyle(.borderedProminent).disabled(working)
                    Button("Request changes") {
                        if confirm("Request changes on #\(number)?", "Your message is posted on GitHub as a review.", button: "Request changes") {
                            run("Changes requested.", reload: true) { await store.review(repo, number, .requestChanges, text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                    }.disabled(blank || working).help(blank ? "Write what should change first" : "Request changes")
                    Spacer()
                    Menu("Close…") {
                        Button("Close pull request") { askClose(deleteBranch: false) }
                        Button("Close and delete its branch", role: .destructive) { askClose(deleteBranch: true) }
                    }.menuStyle(.borderlessButton).fixedSize().disabled(working)
                    Button("Open on GitHub") { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } }
                    if working { ProgressView().controlSize(.small) }
                }
            } else {
                HStack { Text("This pull request is \(pr.state.lowercased()). No further review actions."); Spacer(); Button("Open on GitHub") { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } } }
            }
        }.padding(16)
    }

    var blank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func askClose(deleteBranch: Bool) {
        let msg = deleteBranch
            ? "GitHub cannot delete a pull request, so it is closed. The branch \(pr?.headRefName ?? "") is also deleted, here and on the remote."
            : "GitHub cannot delete a pull request, so it is closed. You can reopen it on GitHub."
        guard confirm("Close #\(number)?", msg, button: deleteBranch ? "Close and delete branch" : "Close") else { return }
        run("Closed.", reload: true) { await store.closePR(repo, number, deleteBranch: deleteBranch) }
    }

    func run(_ ok: String, reload: Bool, _ job: @escaping () async -> String?) {
        working = true
        Task {
            let err = await job()
            working = false
            if let err { result = Banner(text: err, isError: true) }
            else { result = Banner(text: ok, isError: false); text = ""; if reload { await load() } }
        }
    }
}
