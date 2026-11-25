import Foundation

struct GitResult {
    let code: Int32
    let out: String
    let err: String
    var ok: Bool { code == 0 }
    var text: String { (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines) }
}

private final class Box { var data = Data() }

enum Git {
    /// Runs the system git. Nothing is bundled: the app is a thin window over `git`.
    static func run(_ args: [String], in dir: URL) async -> GitResult { await exec("/usr/bin/git", args, in: dir) }

    static func exec(_ exe: String, _ args: [String], in dir: URL) async -> GitResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.currentDirectoryURL = dir
                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"
                env["LC_ALL"] = "C"
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                p.environment = env
                let o = Pipe(), e = Pipe()
                p.standardOutput = o
                p.standardError = e
                do { try p.run() } catch {
                    cont.resume(returning: GitResult(code: 127, out: "", err: "Could not run git: \(error.localizedDescription)"))
                    return
                }
                let ob = Box(), eb = Box()
                let g = DispatchGroup()
                g.enter(); DispatchQueue.global().async { ob.data = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                g.enter(); DispatchQueue.global().async { eb.data = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                p.waitUntilExit()
                g.wait()
                cont.resume(returning: GitResult(code: p.terminationStatus,
                                                 out: String(decoding: ob.data, as: UTF8.self),
                                                 err: String(decoding: eb.data, as: UTF8.self)))
            }
        }
    }
}

struct Change: Identifiable, Hashable {
    let path: String
    let x: Character
    let y: Character
    let untracked: Bool
    var added: Int? = nil
    var deleted: Int? = nil
    var binary = false
    var id: String { path }
    var code: String {
        if untracked { return "?" }
        return String(y != "." ? y : x)
    }
    var isSecret: Bool { Change.looksSecret(path) }

    static func looksSecret(_ path: String) -> Bool {
        let n = (path as NSString).lastPathComponent.lowercased()
        if n == ".env" || n.hasPrefix(".env.") { return !n.hasSuffix(".example") && !n.hasSuffix(".sample") }
        if n.hasPrefix("id_rsa") || n.hasPrefix("id_ed25519") { return !n.hasSuffix(".pub") }
        for ext in [".pem", ".key", ".p12", ".pfx", ".keystore"] where n.hasSuffix(ext) { return true }
        return n.hasPrefix("credentials")
    }
}

struct RepoStatus {
    var branch = ""
    var upstream: String? = nil
    var ahead = 0
    var behind = 0
    var changes: [Change] = []
    var tracked: Int { changes.filter { !$0.untracked }.count }
    var untracked: Int { changes.filter { $0.untracked }.count }
    var added: Int { changes.reduce(0) { $0 + ($1.added ?? 0) } }
    var deleted: Int { changes.reduce(0) { $0 + ($1.deleted ?? 0) } }
}

enum StatusParser {
    /// Parses `git status --porcelain=v2 --branch -z` (stable across git versions).
    static func parse(_ raw: String) -> RepoStatus {
        var s = RepoStatus()
        let recs = raw.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var i = 0
        while i < recs.count {
            let r = recs[i]; i += 1
            if r.hasPrefix("# branch.head ") { s.branch = String(r.dropFirst(14)) }
            else if r.hasPrefix("# branch.upstream ") { s.upstream = String(r.dropFirst(18)) }
            else if r.hasPrefix("# branch.ab ") {
                let p = r.dropFirst(12).split(separator: " ")
                if p.count == 2 { s.ahead = Int(p[0].dropFirst()) ?? 0; s.behind = Int(p[1].dropFirst()) ?? 0 }
            }
            else if r.hasPrefix("1 ") {
                let f = r.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                if f.count == 9 { s.changes.append(mk(String(f[8]), String(f[1]))) }
            }
            else if r.hasPrefix("2 ") {
                let f = r.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                if f.count == 10 { s.changes.append(mk(String(f[9]), String(f[1]))) }
                i += 1 // original path follows
            }
            else if r.hasPrefix("u ") {
                let f = r.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                if f.count == 11 { s.changes.append(mk(String(f[10]), "UU")) }
            }
            else if r.hasPrefix("? ") {
                s.changes.append(Change(path: String(r.dropFirst(2)), x: "?", y: "?", untracked: true))
            }
        }
        return s
    }
    private static func mk(_ path: String, _ xy: String) -> Change {
        let c = Array(xy)
        return Change(path: path, x: c[0], y: c.count > 1 ? c[1] : ".", untracked: false)
    }
    /// Parses `git diff --numstat`: "added<TAB>deleted<TAB>path"; two dashes mean binary.
    static func numstat(_ raw: String) -> [String: (Int?, Int?, Bool)] {
        var m: [String: (Int?, Int?, Bool)] = [:]
        for line in raw.split(separator: "\n") {
            let p = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard p.count == 3 else { continue }
            if p[0] == "-" { m[String(p[2])] = (0, 0, true) }
            else { m[String(p[2])] = (Int(p[0]), Int(p[1]), false) }
        }
        return m
    }
}

struct BranchInfo: Identifiable, Hashable {
    let name: String        // short name, e.g. "main" or "origin/feature"
    let isRemote: Bool
    let isCurrent: Bool
    let track: String       // e.g. "ahead 1, behind 2"
    var id: String { (isRemote ? "r:" : "l:") + name }
    /// The name to give `git switch`: a remote-only branch is created locally with its short name.
    var switchName: String { isRemote ? String(name.drop(while: { $0 != "/" }).dropFirst()) : name }
}

struct CommitInfo: Identifiable, Hashable {
    let hash: String, author: String, when: String, subject: String
    var id: String { hash }
}

struct PullRequest: Identifiable, Decodable, Hashable {
    struct Author: Decodable, Hashable { let login: String }
    let number: Int
    let title: String
    let headRefName: String
    let url: String
    let isDraft: Bool
    let author: Author
    var id: Int { number }
}

struct SideInfo {
    var branches: [BranchInfo] = []
    var incoming: [CommitInfo] = []
    var outgoing: [CommitInfo] = []
    var prs: [PullRequest] = []
    var prNote: String? = nil
}

enum SideParser {
    static func branches(_ raw: String, locals: inout Set<String>) -> [BranchInfo] {
        var out: [BranchInfo] = []
        let rows = raw.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        for r in rows where r.count >= 4 && r[1].hasPrefix("refs/heads/") { locals.insert(r[2]) }
        for r in rows where r.count >= 4 {
            let isRemote = r[1].hasPrefix("refs/remotes/")
            if isRemote && (r[2].hasSuffix("/HEAD") || !r[2].contains("/")) { continue }
            if isRemote && locals.contains(String(r[2].drop(while: { $0 != "/" }).dropFirst())) { continue }
            out.append(BranchInfo(name: r[2], isRemote: isRemote, isCurrent: r[0] == "*", track: r[3].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))))
        }
        return out.sorted { ($0.isCurrent ? 0 : ($0.isRemote ? 2 : 1), $0.name) < ($1.isCurrent ? 0 : ($1.isRemote ? 2 : 1), $1.name) }
    }
    static func commits(_ raw: String) -> [CommitInfo] {
        raw.split(separator: "\n").compactMap { l in
            let p = l.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            return p.count == 4 ? CommitInfo(hash: p[0], author: p[1], when: p[2], subject: p[3]) : nil
        }
    }
}
