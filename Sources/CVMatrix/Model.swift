import Foundation

let outputs = 8
let maxVolts = 5.0

// Out 7 is a gate (Low 0 V / High +5 V, snaps) and Out 8 is a trigger (a short +5 V pulse). The only outputs that jump.
let gateOutput = 6
let trigOutput = 7
let gateVolts = 5.0
let trigSeconds = 0.02

/// When Out 8 fires its trigger for a row.
enum Trig: String, Codable, CaseIterable {
    case none, start, after
    var label: String {
        switch self {
        case .none: return "None"
        case .start: return "At start"
        case .after: return "After glide"
        }
    }
}

func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, x)) }

/// One chapter. `id` is only for SwiftUI; it is not written to the file.
struct Row: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var time: Double
    var glide: Double
    var values: [Double]
    var trig = Trig.none      // Out 8: not part of `values`; only written to the file when it is not .none

    enum CodingKeys: String, CodingKey { case name, time, glide, values, trig }

    init(name: String, time: Double = 60, glide: Double = 10, values: [Double] = []) {
        self.name = name
        self.time = time
        self.glide = glide
        self.values = values
        clean()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 60
        glide = try c.decodeIfPresent(Double.self, forKey: .glide) ?? 10
        values = try c.decodeIfPresent([Double].self, forKey: .values) ?? []
        trig = (try? c.decodeIfPresent(Trig.self, forKey: .trig)) ?? .none
        clean()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(time, forKey: .time)
        try c.encode(glide, forKey: .glide)
        try c.encode(values, forKey: .values)
        if trig != .none { try c.encode(trig, forKey: .trig) }
    }

    /// Same limits as the Python clean_row.
    mutating func clean() {
        name = String(name.prefix(40))
        time = clamp(time, 1, 3600)
        glide = clamp(glide, 0, time)
        values = Array((values + Array(repeating: 0, count: outputs)).prefix(outputs)).map { clamp($0, -maxVolts, maxVolts) }
    }
}

/// The matrix_grid.json layout, compatible with the Python tools.
struct Grid: Equatable, Codable {
    var rows: [Row]
    var speed: Double = 1
    var loop: Bool = false

    static func blank() -> Grid {
        Grid(rows: (1...4).map { Row(name: "Chapter \($0)") })
    }

    init(rows: [Row], speed: Double = 1, loop: Bool = false) {
        self.rows = rows
        self.speed = speed
        self.loop = loop
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = try c.decode([Row].self, forKey: .rows)
        rows = r.isEmpty ? Grid.blank().rows : r
        speed = clamp(try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1, 0.05, 20)
        loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
    }
}
