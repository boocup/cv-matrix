import Foundation
import Observation

@MainActor
@Observable
final class MatrixStore {
    var grid: Grid
    var selected = 0
    var message = ""

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// ~/Library/Application Support/CVMatrix/matrix_grid.json
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CVMatrix", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("matrix_grid.json")
    }()

    init() {
        grid = Grid.blank()
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        do {
            grid = try JSONDecoder().decode(Grid.self, from: Data(contentsOf: Self.fileURL))
        } catch {
            message = "matrix_grid.json could not be read; started with a blank grid"
        }
    }

    /// Replace the grid with a matrix_grid.json from anywhere. Throws if the file is not a grid.
    func load(from url: URL) throws {
        grid = try JSONDecoder().decode(Grid.self, from: Data(contentsOf: url))
        selected = 0
        message = ""
    }

    func addRow() {
        grid.rows.append(Row(name: "Chapter \(grid.rows.count + 1)"))
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

    /// Called after every change; writes the file 250 ms after the last one.
    func scheduleSave() {
        saveTask?.cancel()
        let grid = grid
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try enc.encode(grid).write(to: Self.fileURL, options: .atomic)
            } catch {
                self.message = "could not save: \(error.localizedDescription)"
            }
        }
    }
}
