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

struct PRFile: Decodable, Hashable, Identifiable {
    let path: String
    let additions: Int
    let deletions: Int
    var id: String { path }
}
struct PRPerson: Decodable, Hashable { let login: String }
struct PRComment: Decodable, Hashable, Identifiable {
    let author: PRPerson?
    let body: String
    let createdAt: String?
    var id: String { (createdAt ?? "") + body }
}
struct PRReview: Decodable, Hashable, Identifiable {
    let author: PRPerson?
    let state: String
    let body: String
    let submittedAt: String?
    var id: String { (submittedAt ?? "") + state + body }
}
struct PRDetail: Decodable {
    let number: Int
    let title: String
    let body: String
    let state: String
    let url: String
    let headRefName: String
    let baseRefName: String
    let isDraft: Bool
    let author: PRPerson?
    let additions: Int
    let deletions: Int
    let files: [PRFile]
    let comments: [PRComment]
    let reviews: [PRReview]
    let reviewDecision: String?
    var isOpen: Bool { state == "OPEN" }
    static let fields = "number,title,body,state,url,headRefName,baseRefName,isDraft,author,additions,deletions,files,comments,reviews,reviewDecision"
}

enum PRParser {
    /// Splits `gh pr diff` output into one patch per file, keyed by the new path.
    static func splitDiff(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        var key: String?
        var buf: [Substring] = []
        func flush() { if let k = key { out[k] = buf.joined(separator: "\n") } }
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                flush(); buf = []
                if let r = line.range(of: " b/", options: .backwards) { key = String(line[r.upperBound...]) } else { key = nil }
            }
            buf.append(line)
        }
        flush()
        return out
    }
}

/// How the ignore menu words a pattern for a change. nil means the option does not apply (no folder, no extension).
enum IgnoreScope: CaseIterable {
    case file, folder, ext
    func pattern(for path: String) -> String? {
        let isDir = path.hasSuffix("/")
        let clean = isDir ? String(path.dropLast()) : path
        let ns = clean as NSString
        switch self {
        case .file: return "/" + clean + (isDir ? "/" : "")
        case .folder:
            let d = ns.deletingLastPathComponent
            return d.isEmpty ? nil : "/" + d + "/"
        case .ext:
            let e = ns.pathExtension
            return (e.isEmpty || isDir) ? nil : "*." + e
        }
    }
    func label(for path: String) -> String? {
        guard let p = pattern(for: path) else { return nil }
        switch self {
        case .file: return "Ignore this file"
        case .folder: return "Ignore the folder " + String(p.dropFirst())
        case .ext: return "Ignore all " + p + " files"
        }
    }
}

enum GitHubRemote {
    /// "owner/name" from an origin URL such as git@github.com:owner/name.git or https://github.com/owner/name. nil if not GitHub.
    static func slug(from url: String) -> String? {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var rest: Substring
        if u.hasPrefix("git@github.com:") { rest = u.dropFirst("git@github.com:".count) }
        else if let r = u.range(of: "github.com/"), u.hasPrefix("http") || u.hasPrefix("ssh://") || u.hasPrefix("git://") { rest = u[r.upperBound...] }
        else { return nil }
        if rest.hasSuffix("/") { rest = rest.dropLast() }
        if rest.hasSuffix(".git") { rest = rest.dropLast(4) }
        let parts = rest.split(separator: "/")
        return parts.count == 2 ? parts.joined(separator: "/") : nil
    }
}

struct GitHubRepoItem: Decodable, Identifiable, Hashable {
    let nameWithOwner: String
    let description: String?
    let isPrivate: Bool
    var id: String { nameWithOwner }
}

enum CloneSource {
    /// "owner/name" shorthand (no scheme, no colon, no leading slash): cloned with `gh`, which picks ssh or https from its config.
    static func isShorthand(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(":"), !t.hasPrefix("/"), !t.hasPrefix("."), !t.hasPrefix("~") else { return false }
        let p = t.split(separator: "/", omittingEmptySubsequences: false)
        return p.count == 2 && !p[0].isEmpty && !p[1].isEmpty && !t.contains(" ")
    }
    /// The folder git would pick: the last path part without ".git".
    static func folderName(from s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("/") { t.removeLast() }
        if t.hasSuffix(".git") { t.removeLast(4) }
        let last = t.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return last
    }
}

/// One row of the file tree: a folder (children is a list) or a file (children is nil).
struct FileNode: Identifiable, Hashable {
    let id: String          // the path from the repo root
    let name: String
    var children: [FileNode]?
    var isDir: Bool { children != nil }
}

enum TreeBuilder {
    private final class Dir { var dirs: [String: Dir] = [:]; var files: [String] = [] }

    /// Builds the folder tree from `git ls-files` paths: folders first, then files, each sorted naturally.
    static func build(_ paths: [String]) -> [FileNode] {
        let root = Dir()
        for p in paths {
            let parts = p.split(separator: "/").map(String.init)
            guard let file = parts.last else { continue }
            var d = root
            for part in parts.dropLast() {
                if let n = d.dirs[part] { d = n } else { let n = Dir(); d.dirs[part] = n; d = n }
            }
            d.files.append(file)
        }
        func order(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
        func convert(_ d: Dir, _ prefix: String) -> [FileNode] {
            var out = d.dirs.keys.sorted(by: order).map { k in FileNode(id: prefix + k, name: k, children: convert(d.dirs[k]!, prefix + k + "/")) }
            out += d.files.sorted(by: order).map { FileNode(id: prefix + $0, name: $0, children: nil) }
            return out
        }
        return convert(root, "")
    }
}
