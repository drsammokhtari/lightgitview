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
                            Button("Open") { if let u = URL(string: pr.url) { NSWorkspace.shared.open(u) } }
                            Button("Check out") { Task { await store.checkoutPR(repo, pr) } }.disabled(store.busy)
                        }.controlSize(.small)
                    }.padding(.vertical, 2)
                }
            }
        }
        .font(.callout)
        .task { await store.loadSide(repo) }
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

    /// Discard (trash) and Ignore buttons for a file row or a folder row. Ignore only applies to untracked paths.
    func rowActions(_ files: [String], _ cs: [Change], dir: String? = nil) -> some View {
        HStack(spacing: 6) {
            if !cs.isEmpty && cs.allSatisfy({ $0.untracked }) {
                Button { Task { await store.ignore(repo, dir.map { [$0 + "/"] } ?? files) } } label: { Image(systemName: "eye.slash").frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .help("Ignore: add to .gitignore").accessibilityLabel("Ignore")
            }
            Button { askDiscard(cs) } label: { Image(systemName: "trash").frame(width: 22, height: 22).contentShape(Rectangle()) }
                .help("Discard: remove this change").accessibilityLabel("Discard")
        }.buttonStyle(.borderless).foregroundStyle(.secondary)
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
                                if c.untracked { Button("Ignore (add to .gitignore)") { Task { await store.ignore(repo, [c.path]) } } }
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
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diffText.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, l in
                            Text(l.isEmpty ? " " : String(l))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(l.hasPrefix("+") && !l.hasPrefix("+++") ? Color.green : (l.hasPrefix("-") && !l.hasPrefix("---") ? Color.red : (l.hasPrefix("@@") ? Color.brand : Color.primary)))
                                .textSelection(.enabled)
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
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
