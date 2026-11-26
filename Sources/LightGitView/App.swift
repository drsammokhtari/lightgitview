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
                .frame(minWidth: 1100, minHeight: 600)
                .tint(.brand)
                .fontDesign(.monospaced)
                .task { await store.scan() }
        }
        .defaultSize(width: 1360, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
