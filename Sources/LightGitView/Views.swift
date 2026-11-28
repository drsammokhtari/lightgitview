import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var showSide = true
    @AppStorage("showTree") private var showTree = true
    @State private var showRoots = false
    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let repo = store.selectedRepo {
                // Fixed widths for the columns that must stay readable; only the diff takes the spare room.
                HStack(spacing: 0) {
                    if showTree { FileTreePane(repo: repo).id(repo.id).frame(width: 200); Divider() }
                    RepoDetail(repo: repo).id(repo.id).frame(minWidth: 570, maxWidth: .infinity)
                }
                .inspector(isPresented: $showSide) { SidePanel(repo: repo).id(repo.id).inspectorColumnWidth(min: 260, ideal: 300, max: 380) }
            }
            else { EmptyState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if let r = store.selectedRepo, !store.busy { Task { await store.reload(r) } }
        }
        .sheet(isPresented: $showRoots) { RootsSheet() }
        .sheet(isPresented: $store.showClone) { CloneSheet().environmentObject(store) }
        .sheet(isPresented: $store.showCreate) { CreateRepoSheet().environmentObject(store) }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button("Clone repo…") { store.showClone = true }
                    Button("Create repo…") { store.showCreate = true }
                    Divider()
                    Button("Add repo or repos folder…") { store.addPath() }
                    Button("Manage repos folders…") { showRoots = true }
                } label: { Label("Add repos", systemImage: "plus") }
                .help("Add a repo, or the folder that holds your repos")
            }
            ToolbarItem {
                Button { showTree.toggle() } label: { Label("Files", systemImage: "list.bullet.indent") }
                    .help("Show or hide the repo's folders and files")
            }
            ToolbarItem {
                Button { showSide.toggle() } label: { Label("Branches and pull requests", systemImage: "sidebar.trailing") }
                    .help("Show or hide branches, remote changes and pull requests")
            }
            ToolbarItem {
                Button { Task { await store.syncCurrent() } } label: { Label(store.syncing ? "Syncing…" : "Sync", systemImage: "arrow.triangle.2.circlepath").labelStyle(.titleAndIcon) }
                    .disabled(store.syncing || store.repos.isEmpty)
                    .help("Sync every repo in \(store.currentName): pull what is behind, push the commits you already made. It never commits files. A repo that could conflict is left untouched and tagged.")
                    .keyboardShortcut("s", modifiers: [.command, .shift])
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
            HStack(spacing: 6) {
                workspaceMenu
                Button { Task { await store.syncCurrent() } } label: {
                    if store.syncing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                }
                .buttonStyle(.borderless)
                .disabled(store.syncing || store.repos.isEmpty)
                .help("Sync \(store.currentName): pull what is behind, push the commits you already made. It never commits files. A repo that could conflict is left untouched and tagged.")
                .accessibilityLabel("Sync \(store.currentName)")
            }.padding(.horizontal, 12).padding(.vertical, 8)
            List(selection: $store.selected) {
                Section("\(store.repos.count) repo\(store.repos.count == 1 ? "" : "s")") {
                    ForEach(store.repos) { r in
                        SidebarRow(repo: r, st: store.statuses[r.id], tag: store.syncTags[r.id]).tag(r.id)
                            .contextMenu { repoMenu(r) }
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay { if store.repos.isEmpty && !store.scanning { Text(store.currentWorkspace == nil ? "No repos found" : "No repos in this workspace").foregroundStyle(.secondary) } }
        }
        .onChange(of: store.selected) { _, new in
            if let r = store.selectedRepo, new != nil { Task { await store.reload(r, fetch: true) } }
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
            Button { Task { await store.syncCurrent() } } label: { Label("Sync “\(store.currentName)”", systemImage: "arrow.triangle.2.circlepath") }
                .disabled(store.syncing || store.repos.isEmpty)
            Button("New workspace…") { if let n = promptText("New workspace", "Name, for example Work", "") { store.newWorkspace(named: n) } }
            Button("Manage workspaces…") { showWorkspaces = true }
            if let w = store.currentWorkspace {
                Button("Rename “\(w.name)”…") { if let n = promptText("Rename workspace", "New name", w.name) { store.rename(w, to: n) } }
                Button("Delete “\(w.name)”…", role: .destructive) {
                    if confirm("Delete workspace “\(w.name)”?", "Only the group is deleted. The repos stay on disk and in All repos.", button: "Delete") { store.delete(w) }
                }
            }
            Divider()
            Button("Clone repo…") { store.showClone = true }
            Button("Create repo…") { store.showCreate = true }
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
    var tag: Store.SyncTag? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(repo.name).lineLimit(1)
            if let tag {
                Label(tag.label, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .help(tag.detail)
            }
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
                    .contextMenu { branchMenu(b) }
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
                            Menu("Close…") {
                                Button("Close pull request") { askClosePR(pr, deleteBranch: false) }
                                Button("Close and delete its branch…", role: .destructive) { askClosePR(pr, deleteBranch: true) }
                            }.menuStyle(.borderlessButton).fixedSize().disabled(store.busy)
                        }.controlSize(.small)
                    }.padding(.vertical, 2)
                }
            }
        }
        .font(.callout)
        .task { await store.loadSide(repo) }
        .sheet(item: $reviewing) { pr in PRSheet(repo: repo, number: pr.number).environmentObject(store) }
    }
    // MARK: deleting branches and closing pull requests, with checks first
    enum BranchScope { case local, origin, both }

    @ViewBuilder func branchMenu(_ b: BranchInfo) -> some View {
        if b.isRemote {
            Button("Delete branch on \(b.remoteName ?? "origin")…", role: .destructive) { askDeleteBranch(b, .origin) }
        } else {
            Button("Delete local branch…", role: .destructive) { askDeleteBranch(b, .local) }
                .disabled(b.isCurrent)
            if b.remoteRef != nil {
                Button("Delete branch on \(b.remoteName ?? "origin")…", role: .destructive) { askDeleteBranch(b, .origin) }
                Button("Delete local and \(b.remoteName ?? "origin")…", role: .destructive) { askDeleteBranch(b, .both) }
                    .disabled(b.isCurrent)
            }
        }
    }

    func notify(_ title: String, _ message: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = message; a.addButton(withTitle: "OK"); a.runModal()
    }

    /// Never deletes main, master or the default branch, or the branch you are on. Warns about unmerged commits and open pull requests.
    func askDeleteBranch(_ b: BranchInfo, _ scope: BranchScope) {
        Task {
            let name = b.isRemote ? (b.remoteBranch ?? b.name) : b.name
            let facts = await store.branchFacts(repo, b)
            if facts.isProtected { notify("“\(name)” is protected", "main, master and the remote's default branch are never deleted from here. Do that on GitHub if you really mean it."); return }
            if scope != .origin && b.isCurrent { notify("“\(name)” is checked out", "Switch to another branch first, then delete it."); return }
            var facts_: [String] = []
            if let n = facts.unmerged, n > 0 { facts_.append("\(n) commit\(n == 1 ? "" : "s") on it \(n == 1 ? "is" : "are") not in \(facts.base).") }
            if let pr = facts.openPR, scope != .local { facts_.append("Pull request #\(pr.number) “\(pr.title)” uses this branch. Deleting it on the remote closes that pull request.") }
            let detail = facts_.isEmpty ? "" : "\n\n" + facts_.joined(separator: "\n")
            let remote = b.remoteName ?? "origin"

            if scope == .local {
                guard confirm("Delete the local branch “\(name)”?", "Only the branch on this Mac is deleted. Nothing changes on \(remote)." + detail, button: "Delete") else { return }
                await deleteLocal(name, b)
                return
            }
            let where_ = scope == .both ? "on this Mac and on \(remote)" : "on \(remote)"
            let typed = promptText("Delete “\(name)” \(where_)?", "The branch is removed from \(remote), for everyone who uses it. Anyone with a copy can push it back, but it is gone from the remote until then." + detail + "\n\nType \(name) to confirm.", "")
            guard let typed else { return }
            guard typed.trimmingCharacters(in: .whitespaces) == name else { notify("Name did not match", "Nothing was deleted."); return }
            if scope == .both { guard await deleteLocal(name, b) else { return } }   // local first: a refusal there leaves the remote alone
            if let err = await store.deleteRemoteBranch(repo, remote, name) { store.setError("Could not delete \(name) on \(remote): \(err)") }
            else { store.setInfo(scope == .both ? "Deleted \(name) locally and on \(remote)." : "Deleted \(name) on \(remote).") }
        }
    }

    /// Tries the safe delete first. If git says the branch is not merged, asks before forcing. Returns true when the branch is gone.
    @discardableResult func deleteLocal(_ name: String, _ b: BranchInfo) async -> Bool {
        if let err = await store.deleteLocalBranch(repo, name, force: false) {
            guard err.lowercased().contains("not fully merged") else { store.setError(err); return false }
            guard confirm("“\(name)” has commits that are not merged", "These commits exist only on this branch. If you delete it they are hard to get back. Delete it anyway?", button: "Delete anyway") else { return false }
            if let err2 = await store.deleteLocalBranch(repo, name, force: true) { store.setError(err2); return false }
        }
        store.setInfo("Deleted the local branch \(name).")
        return true
    }

    func askClosePR(_ pr: PullRequest, deleteBranch: Bool) {
        Task {
            if deleteBranch, await store.protectedNames(repo).contains(pr.headRefName) {
                notify("“\(pr.headRefName)” is protected", "The pull request can be closed, but its branch is a protected one and is never deleted from here."); return
            }
            let msg = deleteBranch
                ? "GitHub cannot delete a pull request, so it is closed. The branch \(pr.headRefName) is also deleted, here and on the remote. If it is checked out here, git may keep the local copy."
                : "GitHub cannot delete a pull request, so it is closed. You can reopen it on GitHub."
            guard confirm("Close #\(pr.number) “\(pr.title)”?", msg, button: deleteBranch ? "Close and delete branch" : "Close") else { return }
            if let err = await store.closePR(repo, pr.number, deleteBranch: deleteBranch) { store.setError(err) } else { store.setInfo("Closed #\(pr.number).") }
        }
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
    @State private var openPath: String?        // the file shown in the right-hand pane
    @State private var mode = 0                 // 0 = Changes (diff), 1 = Edit
    @State private var editText = ""
    @State private var editOriginal = ""
    @State private var editBlock: String?       // why this file cannot be edited, if so

    var st: RepoStatus { store.statuses[repo.id] ?? RepoStatus() }
    var ticked: Set<String> { store.ticked[repo.id] ?? [] }
    var message: Binding<String> { Binding(get: { store.messages[repo.id] ?? "" }, set: { store.messages[repo.id] = $0 }) }
    var canCommit: Bool { !message.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ticked.isEmpty && !store.busy }
    var secretsTicked: [Change] { st.changes.filter { $0.isSecret && ticked.contains($0.path) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                changesList.frame(width: 340)
                Divider()
                diffPane.frame(minWidth: 220, maxWidth: .infinity)
            }
            Divider()
            commitBox
        }
        .task { await store.reload(repo, fetch: true) }
        .onChange(of: store.revision[repo.id] ?? 0) { _, _ in Task { await reloadOpenFile() } }
        .onChange(of: store.focusRequest) { _, p in
            if let p { Task { await openFile(p) } }
        }
        .onChange(of: st.changes.map(\.path)) { _, _ in
            guard let p = openPath else { return }
            focus = st.changes.first { $0.path == p }
            if focus == nil && !FileManager.default.fileExists(atPath: url(p).path) { closeFile() }   // discarded or deleted
            else if focus == nil { mode = 1 }                                                       // committed: it stays open, now unchanged
            else { Task { await loadDiff() } }
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
                if let t = store.syncTags[repo.id] {
                    Label("\(t.label): \(t.detail)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
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
            Button { Task { await store.reload(repo, fetch: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
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
        var under: [Change] = []                   // the changes behind those paths
        var isDir: Bool { change == nil }
    }

    /// The list's rows, built in one pass: folder rows come from a map of folder -> changes under it, so a repo with
    /// thousands of changed files stays linear instead of rescanning every change for every folder.
    var rows: [Row] {
        let sorted = st.changes.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
        var under: [String: [Change]] = [:]
        for c in sorted {
            let parts = c.path.split(separator: "/")
            guard parts.count > 1 else { continue }
            var dir = ""
            for p in parts.dropLast() { dir += (dir.isEmpty ? "" : "/") + p; under[dir, default: []].append(c) }
        }
        var out: [Row] = []
        var emitted = Set<String>()
        for c in sorted {
            let parts = c.path.split(separator: "/").map(String.init)
            var hidden = false
            var dir = ""
            for i in 0..<max(parts.count - 1, 0) {
                dir += (i == 0 ? "" : "/") + parts[i]
                if !emitted.contains(dir) {
                    emitted.insert(dir)
                    let cs = under[dir] ?? []
                    out.append(Row(id: "dir:" + dir, depth: i, name: parts[i], change: nil, files: cs.map(\.path), under: cs))
                }
                if collapsed.contains(dir) { hidden = true; break }
            }
            if !hidden { out.append(Row(id: c.path, depth: parts.count - 1, name: (parts.last ?? c.path) + (c.path.hasSuffix("/") ? "/" : ""), change: c, files: [c.path], under: [c])) }
        }
        return out
    }
    func dirOf(_ r: Row) -> String { String(r.id.dropFirst(4)) }

    /// Ignore menu and Discard button for a file row, or Ignore and Discard for a folder row.
    func rowActions(_ files: [String], _ cs: [Change], dir: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let dir {
                Button { askIgnoreFolder(dir, cs) } label: { Image(systemName: "eye.slash").frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .help("Ignore this folder: add it to .gitignore").accessibilityLabel("Ignore folder")
            }
            Button { askDiscard(cs) } label: { Image(systemName: "trash").frame(width: 22, height: 22).contentShape(Rectangle()) }
                .help("Discard: remove this change").accessibilityLabel("Discard")
            Menu {
                if let dir { dirMenu(dir, cs, files) } else if let c = cs.first { fileMenu(c) }
            } label: { Image(systemName: "ellipsis.circle").frame(width: 22, height: 22).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("More actions (also on right-click)").accessibilityLabel("More actions")
        }.buttonStyle(.borderless).foregroundStyle(.secondary)
    }

    // MARK: right-click menus
    func url(_ path: String) -> URL { repo.url.appendingPathComponent(path) }
    func reveal(_ path: String) {
        let u = url(path)
        if FileManager.default.fileExists(atPath: u.path) { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        else { NSWorkspace.shared.activateFileViewerSelecting([u.deletingLastPathComponent()]) }   // deleted files: show the folder
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }

    @ViewBuilder func fileMenu(_ c: Change) -> some View {
        let on = ticked.contains(c.path)
        let exists = FileManager.default.fileExists(atPath: url(c.path).path)
        Button(on ? "Exclude from commit" : "Include in commit") { store.toggle(repo, c.path) }
        Divider()
        Button("Reveal in Finder") { reveal(c.path) }
        Button("Open") { NSWorkspace.shared.open(url(c.path)) }.disabled(!exists)
        Button("Copy path") { copy(c.path) }
        Button("Copy full path") { copy(url(c.path).path) }
        Divider()
        ignoreMenu(c)
        Divider()
        Button("Discard…", role: .destructive) { askDiscard([c]) }
    }

    @ViewBuilder func dirMenu(_ dir: String, _ cs: [Change], _ files: [String]) -> some View {
        let all = files.allSatisfy { ticked.contains($0) }
        Button(all ? "Exclude all from commit" : "Include all in commit") { store.setTicked(repo, files, on: !all) }
        Button(collapsed.contains(dir) ? "Expand" : "Collapse") { if collapsed.contains(dir) { collapsed.remove(dir) } else { collapsed.insert(dir) } }
        Divider()
        Button("Reveal in Finder") { reveal(dir) }
        Button("Copy path") { copy(dir) }
        Button("Copy full path") { copy(url(dir).path) }
        Divider()
        Button("Ignore the folder \(dir)/") { askIgnoreFolder(dir, cs) }
        Divider()
        Button("Discard all in folder…", role: .destructive) { askDiscard(cs) }
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
              VStack(spacing: 0) {
                if let hidden = store.collapsedUntracked[repo.id], hidden > 0 {
                    HStack {
                        Text("\(hidden) untracked files are shown as folders to keep the list fast.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Show all \(hidden) files") { Task { store.showAllUntracked.insert(repo.id); await store.reload(repo) } }
                            .controlSize(.small).help("List every untracked file. A very large list can be slow.")
                    }.padding(8)
                    Divider()
                }
                List(selection: Binding(get: { focus?.id }, set: { id in if let id { Task { await openFile(id) } } })) {
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
                                    Text("+\(a)").foregroundStyle(.green).fixedSize(); Text("−\(d)").foregroundStyle(.red).fixedSize()
                                }
                                rowActions(r.files, [c])
                            }
                            .font(.callout).padding(.leading, CGFloat(r.depth) * 16)
                            .contentShape(Rectangle())
                            .contextMenu { fileMenu(c) }
                            .tag(c.id)
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
                                rowActions(r.files, r.under, dir: dirOf(r))
                            }
                            .font(.callout).padding(.leading, CGFloat(r.depth) * 16)
                            .contentShape(Rectangle())
                            .contextMenu { dirMenu(dirOf(r), r.under, r.files) }
                            .selectionDisabled()
                        }
                    }
                }
              }
            }
        }
    }

    var dirty: Bool { openPath != nil && editBlock == nil && editText != editOriginal }

    var diffPane: some View {
        Group {
            if let p = openPath {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        Text(p).lineLimit(1).truncationMode(.middle)
                        if dirty { Text("● edited").font(.caption).foregroundStyle(Color.brand) }
                        Spacer()
                        if focus != nil {
                            Picker("", selection: $mode) { Text("Changes").tag(0); Text("Edit").tag(1) }
                                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                        } else { Text("no changes").font(.caption).foregroundStyle(.secondary) }
                        if dirty { Button("Revert") { editText = editOriginal }.help("Throw away your edits") }
                        Button("Save") { Task { await saveEdit() } }
                            .keyboardShortcut("s", modifiers: .command).disabled(!dirty)
                            .help("Save the file (⌘S)")
                    }.font(.callout).padding(.horizontal, 12).padding(.vertical, 6)
                    Divider()
                    if mode == 0, focus != nil { DiffView(text: diffText) } else { editor(p) }
                }
            }
            else { Text("Select a file to see or edit it").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }

    @ViewBuilder func editor(_ p: String) -> some View {
        if let why = editBlock {
            VStack(spacing: 8) {
                Text(why).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if FileManager.default.fileExists(atPath: url(p).path) { Button("Open in the default app") { NSWorkspace.shared.open(url(p)) } }
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TextEditor(text: $editText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
        }
    }

    // MARK: opening, editing and saving a file
    /// Shows a file in the right-hand pane: its diff if it has changes (Edit is one click away), otherwise the editor.
    func openFile(_ path: String) async {
        if path == openPath { return }
        if dirty {
            let a = NSAlert()
            a.messageText = "Save changes to \((openPath ?? "").split(separator: "/").last.map(String.init) ?? "this file")?"
            a.informativeText = "Your edits are not saved yet."
            a.addButton(withTitle: "Save"); a.addButton(withTitle: "Don't Save")
            if a.runModal() == .alertFirstButtonReturn { await saveEdit() }
        }
        openPath = path
        focus = st.changes.first { $0.path == path }
        diffText = ""
        mode = focus == nil ? 1 : 0
        let (t, why) = await store.fileForEditing(repo, path)
        editBlock = why; editText = t ?? ""; editOriginal = t ?? ""
        if focus != nil { await loadDiff() }
    }

    /// After any reload: re-read the open file from disk (unless you have unsaved edits) and refresh its diff.
    func reloadOpenFile() async {
        guard let p = openPath else { return }
        let wasDirty = dirty
        focus = st.changes.first { $0.path == p }
        if !wasDirty {
            let (t, why) = await store.fileForEditing(repo, p)
            if t == nil && !FileManager.default.fileExists(atPath: url(p).path) { closeFile(); return }
            editBlock = why; editText = t ?? ""; editOriginal = t ?? ""
        }
        if focus != nil { await loadDiff() } else if mode == 0 { mode = 1 }
    }

    func closeFile() { openPath = nil; focus = nil; diffText = ""; editText = ""; editOriginal = ""; editBlock = nil }

    func saveEdit() async {
        guard let p = openPath, editBlock == nil else { return }
        if let err = await store.saveFile(repo, p, editText) { store.setError("Could not save \(p): \(err)"); return }
        editOriginal = editText
        store.setInfo("Saved \(p).")
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


/// Clone a repo: where from, which folder, and which workspaces it joins.
struct CloneSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var source = ""
    @State private var parent = ""
    @State private var folder = ""
    @State private var folderEdited = false
    @State private var branch = ""
    @State private var picked = Set<String>()
    @State private var newWorkspace = ""
    @State private var cloning = false
    @State private var error: String?
    @State private var mine: [GitHubRepoItem] = []
    @State private var mineNote: String?
    @State private var loadedMine = false

    var parentOptions: [String] { store.roots + (store.roots.contains(parent) || parent.isEmpty ? [] : [parent]) }
    var ready: Bool { !source.trimmingCharacters(in: .whitespaces).isEmpty && !folder.trimmingCharacters(in: .whitespaces).isEmpty && !parent.isEmpty && !cloning }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clone a repo").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Repository").font(.callout.weight(.semibold))
                HStack {
                    TextField("https://github.com/owner/name  or  owner/name", text: $source).textFieldStyle(.roundedBorder)
                    Menu("My GitHub repos") {
                        if mine.isEmpty { Text(mineNote ?? "Loading…") }
                        ForEach(mine) { r in Button((r.isPrivate ? "🔒 " : "") + r.nameWithOwner) { source = r.nameWithOwner } }
                    }.fixedSize().task { if !loadedMine { loadedMine = true; let (i, n) = await store.listGitHubRepos(); mine = i; mineNote = n } }
                }
                Text("A full URL uses git. owner/name uses the GitHub CLI, which picks ssh or https from its settings.").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Clone into").font(.callout.weight(.semibold))
                HStack {
                    Picker("", selection: $parent) {
                        ForEach(parentOptions, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                    Button("Choose…") { chooseParent() }
                }
                HStack {
                    Text("Folder name").foregroundStyle(.secondary)
                    TextField("", text: $folder, onEditingChanged: { _ in }).textFieldStyle(.roundedBorder)
                        .onChange(of: folder) { _, _ in if !folder.isEmpty && folder != CloneSource.folderName(from: source) { folderEdited = true } }
                    TextField("branch (optional)", text: $branch).textFieldStyle(.roundedBorder).frame(width: 170)
                }
                if !parent.isEmpty && !folder.isEmpty { Text("Will be cloned to \(store.cloneDestination(parent: parent, folder: folder).path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspaces").font(.callout.weight(.semibold))
                if store.workspaces.isEmpty { Text("No workspaces yet. Name one below to create it.").font(.caption).foregroundStyle(.secondary) }
                ForEach(store.workspaces) { w in
                    Toggle(w.name, isOn: Binding(get: { picked.contains(w.id) }, set: { on in if on { picked.insert(w.id) } else { picked.remove(w.id) } }))
                }
                TextField("New workspace (optional)", text: $newWorkspace).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }
            if let error { Text(error).foregroundStyle(Color.red).font(.callout).textSelection(.enabled) }
            HStack {
                if cloning { ProgressView().controlSize(.small); Text("Cloning…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(cloning)
                Button("Clone") { clone() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!ready)
            }
        }
        .padding(20).frame(width: 600)
        .onAppear {
            if parent.isEmpty { parent = store.roots.first ?? NSHomeDirectory() }
            if let w = store.currentWorkspace { picked.insert(w.id) }
        }
        .onChange(of: source) { _, new in if !folderEdited { folder = CloneSource.folderName(from: new) } }
    }

    func chooseParent() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Use folder"; p.message = "Choose the folder to clone into"
        if p.runModal() == .OK, let u = p.url { parent = u.path }
    }

    func clone() {
        cloning = true; error = nil
        Task {
            let err = await store.cloneRepo(source: source, parent: parent, folder: folder, branch: branch, workspaceIDs: Array(picked), newWorkspace: newWorkspace)
            cloning = false
            if let err { error = err } else { dismiss() }
        }
    }
}


/// Create a new repo: a local folder with git, and the same repo on GitHub as its origin.
struct CreateRepoSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var o = NewRepo()
    @State private var owners: [String] = []
    @State private var ownersNote: String?
    @State private var ignores: [String] = NewRepo.fallbackGitignores
    @State private var picked = Set<String>()
    @State private var newWorkspace = ""
    @State private var creating = false
    @State private var error: String?

    var parentOptions: [String] { store.roots + (store.roots.contains(o.parent) || o.parent.isEmpty ? [] : [o.parent]) }
    var nameProblem: String? { o.name.isEmpty ? nil : NewRepo.problem(name: o.name) }
    var ready: Bool { !o.name.isEmpty && nameProblem == nil && !o.owner.isEmpty && !o.parent.isEmpty && !creating }
    var targetExists: Bool { !o.name.isEmpty && !o.parent.isEmpty && FileManager.default.fileExists(atPath: store.cloneDestination(parent: o.parent, folder: o.name).path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create a repo").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.callout.weight(.semibold))
                HStack {
                    Picker("", selection: $o.owner) { ForEach(owners, id: \.self) { Text($0).tag($0) } }
                        .labelsHidden().fixedSize().accessibilityLabel("GitHub account")
                    Text("/").foregroundStyle(.secondary)
                    TextField("repo-name", text: $o.name).textFieldStyle(.roundedBorder).accessibilityLabel("Repo name")
                }
                if let p = nameProblem { Text(p).font(.caption).foregroundStyle(Color.red) }
                else if targetExists { Text("A folder with this name already exists there.").font(.caption).foregroundStyle(Color.red) }
                else if let n = ownersNote { Text(n).font(.caption).foregroundStyle(Color.red) }
                TextField("Description (optional)", text: $o.description).textFieldStyle(.roundedBorder).accessibilityLabel("Description")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Visibility").font(.callout.weight(.semibold))
                Picker("", selection: $o.isPrivate) {
                    Text("Private: only you and people you add").tag(true)
                    Text("Public: anyone on the internet can see it").tag(false)
                }.pickerStyle(.radioGroup).labelsHidden().accessibilityLabel("Visibility")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Create in").font(.callout.weight(.semibold))
                HStack {
                    Picker("", selection: $o.parent) { ForEach(parentOptions, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(maxWidth: .infinity)
                    Button("Choose…") { chooseParent() }
                }
                if !o.parent.isEmpty && !o.name.isEmpty { Text("Folder: \(store.cloneDestination(parent: o.parent, folder: o.name).path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Starter files").font(.callout.weight(.semibold))
                HStack(spacing: 16) {
                    Toggle("README", isOn: $o.readme)
                    Text("First branch").foregroundStyle(.secondary)
                    TextField("main", text: $o.branch).textFieldStyle(.roundedBorder).frame(width: 110).accessibilityLabel("First branch name")
                }
                HStack {
                    Picker(".gitignore", selection: $o.gitignore) { Text("None").tag(""); ForEach(ignores, id: \.self) { Text($0).tag($0) } }.frame(width: 260)
                    Picker("License", selection: $o.license) { Text("None").tag(""); ForEach(NewRepo.licenses, id: \.key) { Text($0.name).tag($0.key) } }.frame(width: 220)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspaces").font(.callout.weight(.semibold))
                if store.workspaces.isEmpty { Text("No workspaces yet. Name one below to create it.").font(.caption).foregroundStyle(.secondary) }
                ForEach(store.workspaces) { w in
                    Toggle(w.name, isOn: Binding(get: { picked.contains(w.id) }, set: { on in if on { picked.insert(w.id) } else { picked.remove(w.id) } }))
                }
                TextField("New workspace (optional)", text: $newWorkspace).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }
            if let error { Text(error).foregroundStyle(Color.red).font(.callout).textSelection(.enabled) }
            HStack {
                if creating { ProgressView().controlSize(.small); Text("Creating…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(creating)
                Button("Create and push") { create() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!ready || targetExists)
            }
        }
        .padding(20).frame(width: 600)
        .task {
            if o.parent.isEmpty { o.parent = store.roots.first ?? NSHomeDirectory() }
            if let w = store.currentWorkspace { picked.insert(w.id) }
            let (list, note) = await store.githubOwners()
            owners = list; ownersNote = note
            if o.owner.isEmpty { o.owner = list.first ?? "" }
            ignores = await store.gitignoreTemplates()
        }
    }

    func chooseParent() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Use folder"; p.message = "Choose the folder to create the repo in"
        if p.runModal() == .OK, let u = p.url { o.parent = u.path }
    }

    func create() {
        o.name = o.name.trimmingCharacters(in: .whitespaces)
        o.branch = o.branch.trimmingCharacters(in: .whitespaces)
        if !o.isPrivate && !confirm("Make \(o.owner)/\(o.name) public?", "Anyone on the internet will be able to see this repo and its code.", button: "Create public repo") { return }
        creating = true; error = nil
        Task {
            let err = await store.createRepo(o, workspaceIDs: Array(picked), newWorkspace: newWorkspace)
            creating = false
            if let err { error = err } else { dismiss() }
        }
    }
}


/// A file's text, plain (no diff colours).
struct TextPreview: View {
    let text: String
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text.isEmpty ? " " : text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The second sidebar: the repo's folders and files. Changed files carry their status letter; click one to see its diff,
/// click an unchanged file to read it.
struct FileTreePane: View {
    @EnvironmentObject var store: Store
    let repo: Repo
    @State private var sel: String?

    var st: RepoStatus { store.statuses[repo.id] ?? RepoStatus() }
    var nodes: [FileNode] { store.trees[repo.id] ?? [] }
    var byPath: [String: Change] { Dictionary(st.changes.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }) }
    /// Every folder that has a changed file somewhere below it.
    var dirtyDirs: Set<String> {
        var out = Set<String>()
        for c in st.changes {
            var parts = c.path.split(separator: "/").map(String.init); parts.removeLast()
            var acc = ""
            for p in parts { acc += (acc.isEmpty ? "" : "/") + p; out.insert(acc) }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Files").font(.headline)
                Spacer()
                Button { Task { await store.loadTree(repo) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload the file list").accessibilityLabel("Reload the file list")
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if nodes.isEmpty {
                Text(store.trees[repo.id] == nil ? "Loading…" : "No files").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let changes = byPath, dirty = dirtyDirs
                List(nodes, children: \.children, selection: $sel) { n in
                    HStack(spacing: 6) {
                        Image(systemName: n.isDir ? "folder" : "doc").foregroundStyle(.secondary).frame(width: 14)
                        Text(n.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let c = changes[n.id] {
                            Text(c.code).font(.caption.weight(.bold)).foregroundStyle(c.code == "D" ? Color.red : (c.untracked ? Color.secondary : Color.brand))
                                .accessibilityLabel("changed")
                        } else if n.isDir && dirty.contains(n.id) {
                            Circle().fill(Color.brand).frame(width: 6, height: 6).accessibilityLabel("has changes")
                        }
                    }
                    .font(.callout).contentShape(Rectangle())
                    .contextMenu { menu(n, changes[n.id]) }
                }
                .listStyle(.inset)
                if store.treeTruncated.contains(repo.id) { Text("Showing the first \(Store.treeLimit) files").font(.caption).foregroundStyle(.secondary).padding(6) }
            }
        }
        .task(id: repo.id) { await store.loadTree(repo) }
        .onChange(of: st.changes.map(\.path)) { _, _ in Task { await store.loadTree(repo) } }
        .onChange(of: sel) { _, id in
            guard let id, let n = find(id), !n.isDir else { return }
            store.focusRequest = nil; store.focusRequest = id
        }
    }

    func find(_ id: String) -> FileNode? {
        func walk(_ ns: [FileNode]) -> FileNode? {
            for n in ns { if n.id == id { return n }; if let c = n.children, let f = walk(c) { return f } }
            return nil
        }
        return walk(nodes)
    }

    @ViewBuilder func menu(_ n: FileNode, _ c: Change?) -> some View {
        let u = repo.url.appendingPathComponent(n.id)
        let exists = FileManager.default.fileExists(atPath: u.path)
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([exists ? u : u.deletingLastPathComponent()]) }
        if !n.isDir { Button("Open") { NSWorkspace.shared.open(u) }.disabled(!exists) }
        Button("Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(n.id, forType: .string) }
        Button("Copy full path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(u.path, forType: .string) }
        if c != nil { Divider(); Button("Show its changes") { store.focusRequest = nil; store.focusRequest = n.id } }
    }
}
