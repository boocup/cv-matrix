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

    @ObservationIgnored private var process: Process?
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

    func start(chapters: Int, agentFolder: URL, outputDir: URL, done: @escaping (URL) -> Void) {
        guard !running else { return }
        running = true
        cancelled = false
        progress = "Asking Claude…"
        error = ""
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let command = "cd \(Self.quoted(agentFolder.path)) && PY=.venv/bin/python; [ -x \"$PY\" ] || PY=python3; "
            + "exec \"$PY\" -u chapters.py --backend claude --chapters \(chapters) --write-grid-dir \(Self.quoted(outputDir.path))"
        // A login, interactive shell, so ANTHROPIC_API_KEY from the user's shell setup (.zshrc) is there. Started from a
        // terminal (swift run) an interactive shell would try to use that terminal and be suspended (state T), so first
        // start a new session, which has no controlling terminal.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", "import os,sys; os.setsid(); os.execv('/bin/zsh', ['zsh', '-lic', sys.argv[1]])", command]
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let box = Output()

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let lines = box.addOut(data)
            Task { @MainActor in lines.forEach { self?.note($0) } }
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { box.addErr(data) }
        }
        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let rest = box.addOut(out.fileHandleForReading.readDataToEndOfFile())
            box.addErr(err.fileHandleForReading.readDataToEndOfFile())
            let status = proc.terminationStatus
            Task { @MainActor in
                rest.forEach { self?.note($0) }
                self?.finish(status: status, gridFile: box.gridFile, errorTail: box.errorTail, done: done)
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            running = false
            self.error = "could not start the script: \(error.localizedDescription)"
        }
    }

    func cancel() {
        cancelled = true
        guard let p = process else { return }
        p.terminate()
        // A suspended process only acts on SIGTERM once resumed; make sure it really goes.
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
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
        process = nil
        progress = ""
        if cancelled { return }
        if status == 0, let gridFile, FileManager.default.fileExists(atPath: gridFile) {
            done(URL(fileURLWithPath: gridFile))
        } else {
            error = "Generation failed (exit \(status))" + (errorTail.isEmpty ? "." : ": \(errorTail)")
        }
    }
}
