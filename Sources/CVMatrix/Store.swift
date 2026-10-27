import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MatrixStore {
    var grid: Grid
    var selected = 0
    var message = ""
    private(set) var baseline: Grid  // the grid as last loaded or saved, to tell whether there are unsaved edits
    var dirty: Bool { grid != baseline }
    /// File name of the last grid loaded or saved, minus date/id prefix; Save grid... offers it. Remembered across launches.
    var gridName: String? = UserDefaults.standard.string(forKey: "gridName") {
        didSet { UserDefaults.standard.set(gridName, forKey: Self.gridNameKey) }
    }
    static let gridNameKey = "gridName"
    var autosave = false             // off at every launch: edits are not written to disk unless this is ticked

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// ~/Library/Application Support/CVMatrix/matrix_grid.json
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CVMatrix", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("matrix_grid.json")
    }()

    init() {
        var initial = Grid.blank()
        var note = ""
        if FileManager.default.fileExists(atPath: Self.fileURL.path) {
            do {
                initial = try JSONDecoder().decode(Grid.self, from: Data(contentsOf: Self.fileURL))
            } catch {
                note = "matrix_grid.json could not be read; started with a blank grid"
            }
        }
        grid = initial
        baseline = initial
        message = note
    }

    /// ambient-agent checkout used by Generate with Claude (chosen once, remembered).
    static let agentFolderKey = "agentFolder"

    var agentFolder: URL {
        if let saved = UserDefaults.standard.string(forKey: Self.agentFolderKey) { return URL(fileURLWithPath: saved) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("vcv-dev/ambient-agent")
    }

    var agentFolderValid: Bool {
        FileManager.default.fileExists(atPath: agentFolder.appendingPathComponent("chapters.py").path)
    }

    /// Ask for the ambient-agent folder. Returns false if cancelled or the folder has no chapters.py.
    @discardableResult
    func chooseAgentFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose your ambient-agent folder (the one with chapters.py)"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("chapters.py").path) else {
            message = "\(url.lastPathComponent) has no chapters.py"
            return false
        }
        UserDefaults.standard.set(url.path, forKey: Self.agentFolderKey)
        return true
    }

    /// ~/Documents/CV Matrix: where Save grid..., Load grid... and Generate with Claude keep grid files, so they are all in one
    /// place you can see in Finder. (The autosave file stays in Application Support; it is the app's own copy.)
    static let gridsDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/CV Matrix", isDirectory: true)

    static var generatedDir: URL { gridsDir }

    /// The grids folder, created if needed, for a file panel to start in.
    static func gridsDirForPanel() -> URL {
        try? FileManager.default.createDirectory(at: gridsDir, withIntermediateDirectories: true)
        return gridsDir
    }

    /// Replace the grid with a matrix_grid.json from anywhere. Throws if the file is not a grid.
    func load(from url: URL) throws {
        grid = try JSONDecoder().decode(Grid.self, from: Data(contentsOf: url))
        gridName = Self.unprefixed(url.deletingPathExtension().lastPathComponent)
        baseline = grid
        selected = 0
        message = ""
    }

    /// "2026-10-15-1003-quiet-dawn" and "p2-0138-selvage" become "quiet-dawn" and "selvage".
    nonisolated static func unprefixed(_ name: String) -> String {
        let stripped = name.replacingOccurrences(of: #"^(\d{4}-\d{2}-\d{2}-\d{4}-|p\d+-\d+-)"#, with: "", options: .regularExpression)
        return stripped.isEmpty ? name : stripped
    }

    func addRow() {
        var row = Row(name: "Chapter \(grid.rows.count + 1)")
        row.trig = grid.rows.last?.trig ?? .none          // new rows keep the trigger setting you are using
        grid.rows.append(row)
    }

    func setAllTrigs(_ trig: Trig) {
        for i in grid.rows.indices { grid.rows[i].trig = trig }
    }

    func duplicate(_ id: Row.ID) {
        guard let i = grid.rows.firstIndex(where: { $0.id == id }) else { return }
        var copy = grid.rows[i]
        copy.id = UUID()
        grid.rows.insert(copy, at: i + 1)
    }

    func delete(_ id: Row.ID) {
        guard grid.rows.count > 1, let i = grid.rows.firstIndex(where: { $0.id == id }) else { return }
        grid.rows.remove(at: i)
        selected = min(selected, grid.rows.count - 1)
    }

    nonisolated static func write(_ grid: Grid, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(grid).write(to: url, options: .atomic)
    }

    /// Save a copy of the grid wherever the user chooses (matrix_grid.json format).
    func save(to url: URL) throws {
        try Self.write(grid, to: url)
        gridName = url.deletingPathExtension().lastPathComponent
        baseline = grid
    }

    /// Called after every change; writes the file 250 ms after the last one.
    func scheduleSave() {
        saveTask?.cancel()
        guard autosave else { return }
        let grid = grid
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            do {
                try Self.write(grid, to: Self.fileURL)
                self.baseline = grid
            } catch {
                self.message = "could not save: \(error.localizedDescription)"
            }
        }
    }
}
