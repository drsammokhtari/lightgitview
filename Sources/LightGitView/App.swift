import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
extension Color {
    /// #0F766E on light, #5EEAD4 on dark (readable text). The icon uses the same teal.
    static let brand = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x5EEAD4) : NSColor(hex: 0x0F766E)
    })
}

@main
struct LightGitViewApp: App {
    @StateObject private var store = Store()
    init() {
        // Headless check used by scripts/selftest.sh: prints what the app would show, then exits.
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--selftest"), i + 1 < a.count {
            let ws = URL(fileURLWithPath: a[i + 1])
            Task { @MainActor in
                Store.captureRoot = ws.path   // keeps the check from writing the saved settings
                let s = Store(); s.roots = [ws.path]; s.extraRepos = []
                await s.scan()
                for r in s.repos {
                    let t = s.statuses[r.id] ?? RepoStatus()
                    print("\(r.name) branch=\(t.branch) upstream=\(t.upstream ?? "-") ahead=\(t.ahead) behind=\(t.behind) changed=\(t.tracked) untracked=\(t.untracked) added=\(t.added) deleted=\(t.deleted)")
                }
                // New features, checked on the sample repos.
                if let alpha = s.allRepos.first(where: { $0.name == "alpha-api" }) {
                    await s.ignore(alpha, patterns: [IgnoreScope.ext.pattern(for: "notes.txt")!])
                    print("ignore-ext notes-listed=\(s.statuses[alpha.id]?.changes.contains { $0.path == "notes.txt" } ?? true) gitignore-listed=\(s.statuses[alpha.id]?.changes.contains { $0.path == ".gitignore" } ?? false)")
                    await s.ignore(alpha, patterns: [IgnoreScope.file.pattern(for: "README.md")!], untrack: ["README.md"])
                    let rd = s.statuses[alpha.id]?.changes.first { $0.path == "README.md" }
                    print("ignore-tracked README code=\(rd?.code ?? "gone")")
                }
                print("scopes \(IgnoreScope.file.pattern(for: "src/a.py")!) \(IgnoreScope.folder.pattern(for: "src/a.py")!) \(IgnoreScope.ext.pattern(for: "src/a.py")!) \(IgnoreScope.file.pattern(for: "ref/x/")!)")
                print("remotes \(GitHubRemote.slug(from: "git@github.com:me/app.git") ?? "nil") \(GitHubRemote.slug(from: "https://github.com/me/app") ?? "nil") \(GitHubRemote.slug(from: "https://github.com/me/app.git/") ?? "nil") \(GitHubRemote.slug(from: "git@gitlab.com:me/app.git") ?? "nil") \(GitHubRemote.slug(from: "/tmp/x.git") ?? "nil")")
                let tmpParent = NSTemporaryDirectory() + "clone-parent-\(Int.random(in: 1000...9999))"
                try? FileManager.default.createDirectory(atPath: tmpParent, withIntermediateDirectories: true)
                let remote = ws.path + "/.remotes/alpha-api.git"
                let cerr = await s.cloneRepo(source: remote, parent: tmpParent, folder: "alpha-copy", workspaceIDs: [], newWorkspace: "Cloned")
                let inWs = s.workspaces.first { $0.name == "Cloned" }?.repos.contains(tmpParent + "/alpha-copy") ?? false
                let dup = await s.cloneRepo(source: remote, parent: tmpParent, folder: "alpha-copy", workspaceIDs: [])
                let bad = await s.cloneRepo(source: "/no/such/remote.git", parent: tmpParent, folder: "nope", workspaceIDs: [])
                print("clone err=\(cerr ?? "none") listed=\(s.allRepos.contains { $0.name == "alpha-copy" }) inWorkspace=\(inWs) duplicate=\(dup != nil) failedLeftover=\(FileManager.default.fileExists(atPath: tmpParent + "/nope")) folder=\(CloneSource.folderName(from: "git@github.com:me/app.git")) short=\(CloneSource.isShorthand("me/app")) url=\(CloneSource.isShorthand("https://github.com/me/app"))")
                try? FileManager.default.removeItem(atPath: tmpParent)
                let tree = TreeBuilder.build(["src/b.py", "README.md", "src/a/x.txt", "docs/z.md", "src/a/y.txt"])
                let top = tree.map { $0.name + ($0.isDir ? "/" : "") }.joined(separator: ",")
                let srcKids = tree.first { $0.name == "src" }?.children?.map { $0.name + ($0.isDir ? "/" : "") }.joined(separator: ",") ?? "none"
                print("tree top=\(top) src=\(srcKids)")
                if let alpha = s.allRepos.first(where: { $0.name == "alpha-api" }) {
                    await s.loadTree(alpha)
                    print("repotree \((s.trees[alpha.id] ?? []).map { $0.name }.joined(separator: ","))")
                }
                if let alpha = s.allRepos.first(where: { $0.name == "alpha-api" }) {
                    let (t, why) = await s.fileForEditing(alpha, "src/api.py")
                    let (none, missing) = await s.fileForEditing(alpha, "no/such/file.txt")
                    let before = s.statuses[alpha.id]?.added ?? -1
                    let err = await s.saveFile(alpha, "src/api.py", (t ?? "") + "new line 13\n")
                    let after = s.statuses[alpha.id]?.added ?? -1
                    print("edit read=\(t != nil) why=\(why ?? "none") missing=\(none == nil && missing != nil) save=\(err ?? "ok") added=\(before)->\(after)")
                }
                let fixture = #"{"number":7,"title":"Add health check","body":"Adds /health","state":"OPEN","url":"https://example.com/pr/7","headRefName":"feat/health","baseRefName":"main","isDraft":false,"author":{"login":"jordan"},"additions":14,"deletions":3,"files":[{"path":"src/api.py","additions":12,"deletions":3},{"path":"README.md","additions":2,"deletions":0}],"comments":[{"author":{"login":"sam"},"body":"Looks good","createdAt":"2026-11-26T01:00:00Z"}],"reviews":[{"author":{"login":"sam"},"state":"APPROVED","body":"","submittedAt":"2026-11-26T02:00:00Z"}],"reviewDecision":"APPROVED"}"#
                let d = try? JSONDecoder().decode(PRDetail.self, from: Data(fixture.utf8))
                let parts = PRParser.splitDiff("diff --git a/src/api.py b/src/api.py\n+x\ndiff --git a/README.md b/README.md\n-y\n")
                print("pr files=\(d?.files.count ?? -1) comments=\(d?.comments.count ?? -1) reviews=\(d?.reviews.count ?? -1) open=\(d?.isOpen ?? false) diffs=\(parts.keys.sorted().joined(separator: ","))")
                exit(0)
            }
        }
    }
    var body: some Scene {
        WindowGroup("LightGitView") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1380, minHeight: 600)
                .tint(.brand)
                .fontDesign(.monospaced)
                .task { await store.scan() }
        }
        .defaultSize(width: 1500, height: 820)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
