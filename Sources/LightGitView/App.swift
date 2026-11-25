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
