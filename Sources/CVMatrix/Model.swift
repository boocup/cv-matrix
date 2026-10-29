import Foundation

let outputs = 8
let maxVolts = 5.0

// Out 7 is a gate (Low 0 V / High +5 V, snaps) and Out 8 is a trigger (a short +5 V pulse). The only outputs that jump.
let gateOutput = 6
let trigOutput = 7
let gateVolts = 5.0
let trigSeconds = 0.02

/// Out 8's trigger for a row: off, or one pulse at the start of the row. Files from before may say "after" (when the
/// glide finished); that now loads as .start.
enum Trig: String, Codable, CaseIterable {
    case none, start
    var label: String { self == .none ? "Off" : "On" }

    init(from decoder: Decoder) throws {
        self = try decoder.singleValueContainer().decode(String.self) == "none" ? .none : .start
    }
}

// Out 5 shifts pitch up and Out 6 down by one of these intervals (1 V/oct). Other values snap to the nearest on load.
let pitchNames = ["None", "3rd", "5th", "Octave"]
let pitchSteps: [Double] = [0, 4.0 / 12, 7.0 / 12, 1]

func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, x)) }

// Time and Glide are three-way switches. Time is Short 30, Standard 60 or Long 120 s; Glide is Low, Medium or High: a
// quarter, a third or half of the chapter. Grids with other values snap to the nearest positions when they are loaded.
let timeNames = ["Short", "Standard", "Long"]
let glideNames = ["Low", "Medium", "High"]
let timeSteps: [Double] = [30, 60, 120]
let glideDivisors: [Double] = [4, 3, 2]
let glideShareNames = ["¼", "⅓", "½"]

/// One chapter. `id` is only for SwiftUI; it is not written to the file.
struct Row: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var time: Double
    var glide: Double
    var values: [Double]
    var trig = Trig.none      // Out 8: not part of `values`; only written to the file when it is not .none

    enum CodingKeys: String, CodingKey { case name, time, glide, values, trig }

    init(name: String, time: Double = 60, glide: Double = 20, values: [Double] = []) {
        self.name = name
        self.time = time
        self.glide = glide
        self.values = values
        clean()
        snapToSwitches()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 60
        glide = try c.decodeIfPresent(Double.self, forKey: .glide) ?? 10
        values = try c.decodeIfPresent([Double].self, forKey: .values) ?? []
        trig = (try? c.decodeIfPresent(Trig.self, forKey: .trig)) ?? .none
        clean()
        snapToSwitches()
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

    /// Time switch position, 0...2. Nearest on a log scale, so 90 s is High and 75 s is Medium. Setting it keeps the
    /// glide's share of the chapter.
    var timeStep: Int {
        get { timeSteps.indices.min { abs(log(timeSteps[$0] / time)) < abs(log(timeSteps[$1] / time)) }! }
        set { let g = glideStep; time = timeSteps[newValue]; glide = time / glideDivisors[g] }
    }

    /// Glide switch position, 0...2: the nearest of a quarter, a third or half of the chapter.
    var glideStep: Int {
        get {
            let share = glide / time
            return glideDivisors.indices.min { abs(1 / glideDivisors[$0] - share) < abs(1 / glideDivisors[$1] - share) }!
        }
        set { glide = time / glideDivisors[newValue] }
    }

    /// Out 5 (`k` 4, upward) or Out 6 (`k` 5, downward): index into pitchSteps.
    func pitchStep(_ k: Int) -> Int {
        let v = k == 5 ? -values[k] : values[k]
        return pitchSteps.indices.min { abs(pitchSteps[$0] - v) < abs(pitchSteps[$1] - v) }!
    }

    mutating func setPitchStep(_ k: Int, _ step: Int) {
        values[k] = (k == 5 ? -1 : 1) * pitchSteps[step]
    }

    var gateOn: Bool {
        get { values[gateOutput] > gateVolts / 2 }
        set { values[gateOutput] = newValue ? gateVolts : 0 }
    }

    /// Put Time, Glide, the pitch shifts and the gate on positions the controls have.
    mutating func snapToSwitches() {
        let g = glideStep
        time = timeSteps[timeStep]
        glide = time / glideDivisors[g]
        for k in [4, 5] { setPitchStep(k, pitchStep(k)) }
        gateOn = gateOn
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
