//
//  MacProRepo.swift
//  WatDash
//

#if os(macOS)
import Foundation

/// WatDash's own clone of the classes repository, used only for the Mac Pro
/// sync. It lives in Application Support, so WatDash never touches the
/// classes folder you work in (or anything uncommitted there).
///
/// Everything WatDash commits is checked before it's pushed: it may write
/// `Calendar/watdash.json` and delete notes in `Inbox/`, nothing else. git
/// runs in its own process group with no terminal and nothing that can ask
/// for a password, and is killed with its children after a timeout, so an
/// offline Mac or a missing login fails fast instead of hanging.
///
/// Synchronous: call from a background task.
final class MacProRepo: @unchecked Sendable {
    static let exportPath = "Calendar/watdash.json"
    static let authorName = "WatDash (MacBook)"
    static let authorEmail = "watdash@macbook.local"

    struct GitResult {
        var status: Int32
        var output: String
        var timedOut: Bool
        var ok: Bool { status == 0 && !timedOut }
    }

    struct Failure: LocalizedError {
        var summary: String
        var output: String = ""
        var errorDescription: String? { summary }
    }

    let directory: URL
    let remote: String
    let git: String

    init(directory: URL, remote: String, git: String = "/usr/bin/git") {
        self.directory = directory
        self.remote = remote
        self.git = git
    }

    private var branch = "main"
    private var upstream: String { "origin/\(branch)" }

    // MARK: - Running git

    func run(_ arguments: [String], timeout: TimeInterval = 120, in folder: URL? = nil) -> GitResult {
        var environment = ProcessInfo.processInfo.environment
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"] { environment.removeValue(forKey: key) }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/false"
        environment["SSH_ASKPASS"] = "/usr/bin/false"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"
        environment["GIT_HTTP_LOW_SPEED_LIMIT"] = "1000"
        environment["GIT_HTTP_LOW_SPEED_TIME"] = "30"
        environment["GIT_MERGE_AUTOEDIT"] = "no"
        environment["GIT_EDITOR"] = "/usr/bin/true"
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        environment.removeValue(forKey: "DISPLAY")
        let args = [git] + arguments
        return Self.spawn(args, environment: environment, directory: (folder ?? directory).path, timeout: timeout)
    }

    /// posix_spawn into a new process group, so a timeout can stop git and
    /// whatever it started (ssh, the https helper, the credential helper).
    private static func spawn(_ args: [String], environment: [String: String], directory: String, timeout: TimeInterval) -> GitResult {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return GitResult(status: 126, output: "pipe failed", timedOut: false) }
        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        posix_spawn_file_actions_addchdir_np(&actions, directory)
        var attributes: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        sigfillset(&defaults)
        sigdelset(&defaults, SIGKILL)
        sigdelset(&defaults, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &defaults)

        let argv = args.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        var pid: pid_t = 0
        let error = posix_spawn(&pid, args[0], &actions, &attributes, argv, envp)
        close(fds[1])
        guard error == 0 else {
            close(fds[0])
            return GitResult(status: 127, output: "git couldn't be started: \(String(cString: strerror(error)))", timedOut: false)
        }

        // The timeout and the reaping share one queue, so the group is never
        // signalled once its leader's pid could have been reused.
        let guardQueue = DispatchQueue(label: "watdash.macpro.git")
        var finished = false
        var timedOut = false
        guardQueue.asyncAfter(deadline: .now() + timeout) {
            guard !finished else { return }
            timedOut = true
            kill(-pid, SIGTERM)
            guardQueue.asyncAfter(deadline: .now() + 5) { if !finished { kill(-pid, SIGKILL) } }
        }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(fds[0], &buffer, buffer.count)
            if count > 0 {
                if output.count < 512 * 1024 { output.append(buffer, count: count) }
                continue
            }
            if count < 0 && errno == EINTR { continue }
            break
        }
        close(fds[0])
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1 && errno == EINTR {}
        guardQueue.sync { finished = true }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        let exited = (status & 0x7f) == 0
        let code = exited ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        let text = String(decoding: output, as: UTF8.self)
        return GitResult(status: code, output: text, timedOut: timedOut)
    }

    // MARK: - The clone

    /// Clones the repository the first time; afterwards makes sure `origin`
    /// still points where Settings says.
    func prepare() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.appendingPathComponent(".git/HEAD").path) {
            if fm.fileExists(atPath: directory.path) { try? fm.removeItem(at: directory) }
            try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            let result = run(["clone", "--quiet", "--no-tags", remote, directory.path], timeout: 600,
                             in: directory.deletingLastPathComponent())
            guard result.ok else {
                try? fm.removeItem(at: directory)
                throw Self.failure(result, doing: "clone the repository")
            }
        } else {
            let current = run(["remote", "get-url", "origin"]).output.trimmed
            if current != remote { _ = run(["remote", "set-url", "origin", remote]) }
        }
        let head = run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]).output.trimmed
        if head.hasPrefix("origin/"), head.count > 7 { branch = String(head.dropFirst(7)) }
    }

    /// `git pull --rebase`, in steps: fetch, then replay any commit an
    /// earlier push didn't get out. If that can't be replayed, the clone is
    /// put back to the remote branch: everything WatDash commits here can be
    /// made again (the export is rebuilt, and applied notes are remembered).
    func pull() throws {
        let fetch = run(["fetch", "--quiet", "--prune", "origin"])
        guard fetch.ok else { throw Self.failure(fetch, doing: "fetch") }
        _ = run(["reset", "--quiet", "--hard"])
        if !run(["rebase", "--quiet", upstream]).ok {
            _ = run(["rebase", "--abort"])
            let reset = run(["reset", "--quiet", "--hard", upstream])
            guard reset.ok else { throw Self.failure(reset, doing: "catch up with GitHub") }
        }
    }

    /// The notes waiting in Inbox/: path → text.
    func inbox() -> [(path: String, text: String)] {
        let folder = directory.appendingPathComponent(MacProInbox.folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name in
            let path = "\(MacProInbox.folder)/\(name)"
            guard MacProInbox.isNotePath(path),
                  let data = try? Data(contentsOf: folder.appendingPathComponent(name)), data.count <= 64 * 1024 else { return nil }
            return (path, String(decoding: data, as: UTF8.self))
        }
    }

    func currentExport() -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(Self.exportPath))
    }

    /// Writes the export, deletes the consumed notes, commits, and pushes,
    /// rebasing over anything pushed meanwhile. Returns whether a push went out.
    func publish(export: Data, consumed: [String], message: String) throws -> Bool {
        for attempt in 0..<3 {
            let file = directory.appendingPathComponent(Self.exportPath)
            if (try? Data(contentsOf: file)) != export {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try export.write(to: file, options: .atomic)
            }
            _ = run(["add", "--", Self.exportPath])
            for path in consumed where MacProInbox.isNotePath(path)
                && FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path) {
                _ = run(["rm", "--quiet", "--", path])
            }
            let staged = run(["diff", "--cached", "--name-status"]).output
                .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            if let stray = staged.first(where: { !Self.isAllowedChange($0) }) {
                _ = run(["reset", "--quiet", "--hard"])
                throw Failure(summary: "Refused to commit \(stray.replacingOccurrences(of: "\t", with: " ")): WatDash only writes Calendar/ and deletes notes in Inbox/.")
            }
            if !staged.isEmpty {
                let commit = run(["-c", "user.name=\(Self.authorName)", "-c", "user.email=\(Self.authorEmail)",
                                  "commit", "--quiet", "--no-verify", "-m", message])
                guard commit.ok else { throw Self.failure(commit, doing: "commit") }
            }
            let ahead = run(["rev-list", "--count", "\(upstream)..HEAD"]).output.trimmed
            if ahead == "0" { return false }
            let push = run(["push", "--quiet", "--porcelain", "origin", "HEAD:refs/heads/\(branch)"])
            if push.ok { return true }
            let said = push.output.lowercased()
            let raced = said.contains("[rejected]") || said.contains("fetch first") || said.contains("non-fast-forward")
            guard raced, attempt < 2 else { throw Self.failure(push, doing: "push") }
            // Someone (the Mac Pro, Claude) pushed meanwhile: build on that.
            try pull()
        }
        return false
    }

    /// `git diff --name-status` lines WatDash may commit.
    static func isAllowedChange(_ line: String) -> Bool {
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        switch parts[0] {
        case "A", "M": return parts[1] == exportPath
        case "D": return MacProInbox.isNotePath(parts[1])
        default: return false
        }
    }

    // MARK: - Messages

    static func failure(_ result: GitResult, doing what: String) -> Failure {
        let said = result.output.lowercased()
        let summary: String
        if result.timedOut {
            summary = "git gave up after waiting (\(what)). The network may be slow or down."
        } else if ["could not resolve host", "network is unreachable", "no route to host", "connection timed out",
                   "operation timed out", "failed to connect", "connection refused", "couldn't connect"].contains(where: said.contains) {
            summary = "Couldn't reach GitHub. Is the MacBook online?"
        } else if said.contains("authentication failed") || said.contains("could not read username")
                    || said.contains("terminal prompts disabled") || said.contains("permission denied (publickey") {
            summary = "GitHub didn't accept this Mac's login for the repository."
        } else if said.contains("repository not found") || said.contains("does not appear to be a git repository") {
            summary = "GitHub says the repository isn't there, or this Mac can't see it."
        } else if let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("fatal: ") || $0.hasPrefix("error: ") }) {
            summary = "git couldn't \(what): \(line.split(separator: " ", maxSplits: 1).last.map(String.init) ?? "")"
        } else {
            summary = "git couldn't \(what) (status \(result.status))."
        }
        return Failure(summary: summary, output: result.output)
    }
}
#endif
