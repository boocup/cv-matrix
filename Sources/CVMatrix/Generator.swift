import Foundation
import Observation

/// Runs `chapters.py` from the user's ambient-agent folder with the Claude backend and reports the grid file it wrote.
/// The app makes no network call itself and never sees the API key: the script runs in a login shell, which is where
/// ANTHROPIC_API_KEY lives, and the key stays in that process.
@MainActor
@Observable
final class Generator {
    private(set) var running = false
    private(set) var progress = ""
    private(set) var error = ""

    @ObservationIgnored private var pid: pid_t = 0
    @ObservationIgnored private var cancelled = false

    /// Collects the script's output off the main thread.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var partial = Data()
        private var errLines: [String] = []
        private var grid: String?

        func addOut(_ data: Data) -> [String] {
            lock.lock(); defer { lock.unlock() }
            partial.append(data)
            var lines: [String] = []
            while let nl = partial.firstIndex(of: 10) {
                let line = String(decoding: partial[..<nl], as: UTF8.self)
                partial = partial[(nl + 1)...]
                if line.hasPrefix("GRID_FILE: ") { grid = String(line.dropFirst("GRID_FILE: ".count)) }
                lines.append(line)
            }
            return lines
        }

        func addErr(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            errLines += String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        }

        var gridFile: String? { lock.lock(); defer { lock.unlock() }; return grid }
        var errorTail: String {
            lock.lock(); defer { lock.unlock() }
            let useful = errLines.filter { !$0.isEmpty && !$0.contains("can't set tty") && !$0.contains("no job control") }
            return useful.suffix(3).joined(separator: " ")
        }
    }

    private static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func start(chapters: Int, voices: Int, brief: String, agentFolder: URL, outputDir: URL, done: @escaping (URL) -> Void) {
        guard !running else { return }
        running = true
        cancelled = false
        progress = "Asking Claude…"
        error = ""
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let trimmed = brief.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let briefArg = trimmed.isEmpty ? "" : " --brief \(Self.quoted(String(trimmed.prefix(1500))))"
        let command = "cd \(Self.quoted(agentFolder.path)) && PY=.venv/bin/python; [ -x \"$PY\" ] || PY=python3; "
            + "exec \"$PY\" -u chapters.py --backend claude --chapters \(chapters) --voices \(voices)\(briefArg) --write-grid-dir \(Self.quoted(outputDir.path))"
        let box = Output()
        let spawned: (pid: pid_t, out: FileHandle, err: FileHandle)
        do {
            spawned = try Self.spawnShell(command)
        } catch {
            running = false
            self.error = "could not start the script: \(error.localizedDescription)"
            return
        }
        pid = spawned.pid
        let (out, err) = (spawned.out, spawned.err)

        out.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let lines = box.addOut(data)
            Task { @MainActor in lines.forEach { self?.note($0) } }
        }
        err.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { box.addErr(data) }
        }
        let child = spawned.pid
        Thread.detachNewThread { [weak self] in
            var raw: Int32 = 0
            while waitpid(child, &raw, 0) < 0 && errno == EINTR {}
            out.readabilityHandler = nil
            err.readabilityHandler = nil
            let rest = box.addOut(out.readDataToEndOfFile())
            box.addErr(err.readDataToEndOfFile())
            let status: Int32 = (raw & 0x7f) == 0 ? (raw >> 8) & 0xff : 128 + (raw & 0x7f)   // exit code, or 128 + signal
            Task { @MainActor in
                rest.forEach { self?.note($0) }
                self?.finish(status: status, gridFile: box.gridFile, errorTail: box.errorTail, done: done)
            }
        }
    }

    /// Start `/bin/zsh -lic command` in a NEW SESSION (no controlling terminal). A login, interactive shell is what
    /// brings in ANTHROPIC_API_KEY from the user's .zshrc; started from a terminal (swift run) without a new session it
    /// would try to use that terminal and be suspended.
    private static func spawnShell(_ command: String) throws -> (pid: pid_t, out: FileHandle, err: FileHandle) {
        var outPipe: [Int32] = [0, 0], errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0, pipe(&errPipe) == 0 else { throw POSIXError(.EMFILE) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
        for fd in outPipe + errPipe { posix_spawn_file_actions_addclose(&actions, fd) }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        let args = ["zsh", "-lic", command]
        let env = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, "/bin/zsh", &actions, &attr, argv, envp)
        close(outPipe[1]); close(errPipe[1])
        guard rc == 0 else {
            close(outPipe[0]); close(errPipe[0])
            throw POSIXError(POSIXErrorCode(rawValue: rc) ?? .EPERM)
        }
        return (pid, FileHandle(fileDescriptor: outPipe[0], closeOnDealloc: true),
                FileHandle(fileDescriptor: errPipe[0], closeOnDealloc: true))
    }

    func cancel() {
        cancelled = true
        guard pid > 0 else { return }
        let target = pid
        kill(-target, SIGTERM)                    // the whole session, in case the script started anything
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if self.pid == target { kill(-target, SIGKILL) }     // still there (e.g. suspended)
        }
    }

    /// "3. Hollow Drift   env1 0.20 ..." becomes "Chapter 3: Hollow Drift".
    private func note(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].hasSuffix("."), Int(parts[0].dropLast()) != nil else { return }
        let name = parts[1].components(separatedBy: "  ").first ?? String(parts[1])
        progress = "Chapter \(parts[0].dropLast()) written: \(name.trimmingCharacters(in: .whitespaces))"
    }

    private func finish(status: Int32, gridFile: String?, errorTail: String, done: (URL) -> Void) {
        running = false
        pid = 0
        progress = ""
        if cancelled { return }
        if status == 0, let gridFile, FileManager.default.fileExists(atPath: gridFile) {
            done(URL(fileURLWithPath: gridFile))
        } else {
            error = "Generation failed (exit \(status))" + (errorTail.isEmpty ? "." : ": \(errorTail)")
        }
    }
}
