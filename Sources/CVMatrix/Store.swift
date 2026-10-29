import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class MatrixStore {
    var grid: Grid
    var selected = 0
    var message = ""
    /// The grid file Save writes to: the one last opened or saved. Remembered across launches and reopened at launch.
    private(set) var fileURL: URL? = UserDefaults.standard.url(forKey: "gridFile") {
        didSet { UserDefaults.standard.set(fileURL, forKey: "gridFile") }
    }
    private(set) var baseline: Grid  // the grid as last opened or saved, to tell whether there are unsaved edits
    var dirty: Bool { grid != baseline }
    /// File name of the last grid opened or saved, minus date/id prefix; Save As… offers it. Remembered across launches.
    var gridName: String? = UserDefaults.standard.string(forKey: "gridName") {
        didSet { UserDefaults.standard.set(gridName, forKey: "gridName") }
    }

    /// ~/Library/Application Support/CVMatrix/matrix_grid.json, where older versions autosaved. Opened at launch only
    /// when there is no grid file to reopen.
    static let legacyURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CVMatrix/matrix_grid.json")

    init() {
        var initial = Grid.blank()
        var note = ""
        let reopen = UserDefaults.standard.url(forKey: "gridFile")
        if let url = reopen ?? (FileManager.default.fileExists(atPath: Self.legacyURL.path) ? Self.legacyURL : nil) {
            do {
                initial = try JSONDecoder().decode(Grid.self, from: Data(contentsOf: url))
            } catch {
                note = "\(url.lastPathComponent) could not be read; started with a blank grid"
            }
        }
        grid = initial
        baseline = initial
        message = note
        if reopen != nil && !note.isEmpty { fileURL = nil }
    }

    /// ~/Documents/CV Matrix: where Open… and Save… start, so grid files are all in one place you can see in Finder.
    static let gridsDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/CV Matrix", isDirectory: true)

    /// The grids folder, created if needed, for a file panel to start in.
    static func gridsDirForPanel() -> URL {
        try? FileManager.default.createDirectory(at: gridsDir, withIntermediateDirectories: true)
        return gridsDir
    }

    /// Replace the grid with a matrix_grid.json from anywhere. Throws if the file is not a grid.
    func load(from url: URL) throws {
        grid = try JSONDecoder().decode(Grid.self, from: Data(contentsOf: url))
        gridName = Self.unprefixed(url.deletingPathExtension().lastPathComponent)
        fileURL = url
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

    /// Save to the current file, or ask for one if there is none. Returns false if it was not saved.
    @discardableResult
    func save() -> Bool {
        guard let url = fileURL else { return saveAs() }
        return write(to: url)
    }

    /// Ask where to save, offering the current name, and save there. Returns false if cancelled or not saved.
    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = (gridName ?? "matrix_grid") + ".json"
        panel.directoryURL = fileURL?.deletingLastPathComponent() ?? Self.gridsDirForPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(to: url)
    }

    private func write(to url: URL) -> Bool {
        do {
            try Self.write(grid, to: url)
        } catch {
            message = "could not save \(url.lastPathComponent): \(error.localizedDescription)"
            return false
        }
        fileURL = url
        gridName = url.deletingPathExtension().lastPathComponent
        baseline = grid
        message = ""
        return true
    }

    /// Before something would throw away unsaved edits (opening another grid, quitting): ask to save them.
    /// Returns true to go ahead.
    func confirmDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(fileURL?.lastPathComponent ?? "this grid")?"
        alert.informativeText = "Your changes are lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: baseline = grid; return true
        default: return false
        }
    }
}
