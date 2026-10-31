import Foundation

/// Writes the grid as an OXI ONE MKII project (firmware 2.2.10), so the OXI can play it without the Mac.
/// Out 1-7 become seq 1 mod lanes 1-7, routed to CV 1-7 as MOD 1-7; the gate (Out 7) snaps instead of gliding.
/// Out 8's triggers become notes on seq 2 (Mono, Div Bar), routed to Gate 1 as Trig.
/// A port of conductor/oxi_project.py in ~/vcv-dev/llm, whose OXI_EXPORT_NOTES.md has the file format; both write the
/// same bytes for the same grid.
enum OXIExport {
    struct Summary {
        var steps: Int
        var step: Double   // seconds per lane step
        var bpm: Double
    }

    enum Failure: LocalizedError {
        case tooLong(seconds: Double, limit: Double)
        var errorDescription: String? {
            switch self {
            case .tooLong(let seconds, let limit):
                return "the grid runs \(minutes(seconds)); an OXI pattern holds at most \(minutes(limit)) (128 steps)"
            }
        }
    }

    static func minutes(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s"
    }

    /// Always the same name, so it lands in the same slot in the OXI App and never needs renaming on the device.
    static let destination: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/Projects/cvm.oxipro")

    static let preferredStep = 3.75   // 64 BPM; longer grids get longer steps
    static let maxStep = 12.0         // 20 BPM, the OXI's lowest tempo

    // Header
    static let tempo = 0x10           // BPM x 10, u16 little-endian
    static let name = 4               // 12 bytes, NUL padded
    static let headerCRC = 0x2A40     // checksum of the bytes before it, stored here
    static let cvSeq = 0x204B         // CV routing, 8 entries indexed by CV out: sequencer bitmask (1 = seq 1)
    static let cvType = 0x2053        // MOD n = 4 + n
    static let cvVoice = 0x205B       // seq 1's voice per CV out
    static let cvOffset = 0x20A3      // offset + 100
    static let gateSeq = 0x20B3       // gate routing, 8 entries indexed by gate out: sequencer
    static let gateType = 0x20BB      // 0 = Trig
    static let seqVoices = 0x20C3     // 8 bytes per sequencer: voice n -> gate out (0-based), 255 = none

    // Seq 1, pattern 1 (Stochastic): mod lanes
    static let lanePattern = 0x3000
    static let rec = 15               // step record: 7 note bytes, then lanes 1-8
    static let val = 10               // lane n of step k is at rec * k + val + n
    static let active = 0x7EA         // per-lane arrays, lane n at offset + n - 1
    static let smooth = 0x8E7
    static let end = 0x8F7            // last step, 0-based
    static let laneX = 0x8FF          // unknown; copied from lane 1, which plays correctly
    static let div = 0x907            // 0 = Bar
    static let laneCRC = 0xAE8

    // Seq 2, pattern 1 (Mono): triggers
    static let trigPattern = 0x3000 + 16 * 0x3000
    static let monoRec = 24           // step record from byte 4: note (255 = none), velocity, -, gate length %
    static let note: UInt8 = 4        // any note; only its gate is used
    static let trigLength: UInt8 = 1  // % of a step
    static let monoEnds = [(0xCA9, 4), (0xD65, 8)]
    static let monoLength = 0xF16
    static let monoCRC = 0xF58

    static let patternSize = 0x3000

    /// Export to `destination`, creating ~/Downloads/Projects if needed.
    static func export(_ grid: Grid) throws -> Summary {
        let (data, summary) = try project(for: grid)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return summary
    }

    static func project(for grid: Grid) throws -> (Data, Summary) {
        let step = try chooseStep(grid)
        var d = [UInt8](template())

        var p = Array(d[lanePattern..<lanePattern + patternSize])
        for lane in 1...7 {
            let volts = laneSteps(grid, out: lane - 1, step: step)
            for k in 0..<128 {                       // lane values 0...127 give 0...5 V, 0...-127 give 0...-3 V
                let v = k < volts.count ? volts[k] : 0
                let x = Int((v / (v >= 0 ? 5 : 3) * 127).rounded(.toNearestOrEven))
                p[k * rec + val + lane] = UInt8(bitPattern: Int8(max(-127, min(127, x))))
            }
            let i = lane - 1
            p[active + i] = 1
            p[smooth + i] = 0
            p[end + i] = UInt8(volts.count - 1)
            p[laneX + i] = p[laneX]
            p[div + i] = 0
            d[cvSeq + i] = 1
            d[cvType + i] = UInt8(4 + lane)
            d[cvVoice + i] = 0
            d[cvOffset + i] = 100
        }
        put(crc(p[0..<laneCRC]), into: &p, at: laneCRC)
        d.replaceSubrange(lanePattern..<lanePattern + patternSize, with: p)

        writeTriggers(grid, step: step, into: &d)

        let bpmx10 = Int((4 * 60 / step * 10).rounded(.toNearestOrEven))   // a Bar step is one 4/4 bar
        d[tempo] = UInt8(bpmx10 & 0xFF)
        d[tempo + 1] = UInt8(bpmx10 >> 8)
        let title = Array("cvm".utf8)
        for i in 0..<12 { d[name + i] = i < title.count ? title[i] : 0 }
        put(crc(d[0..<headerCRC]), into: &d, at: headerCRC)

        return (Data(d), Summary(steps: totalSteps(grid, step), step: step, bpm: Double(bpmx10) / 10))
    }

    /// The shortest step from 3.75 s up whose 128 steps hold the whole grid. Steps divide a 30 s chapter evenly (30 / m
    /// at speed 1), so every chapter keeps its exact length: 3.75, 4.29, 5, 6, 7.5 or 10 s.
    static func chooseStep(_ grid: Grid) throws -> Double {
        let chapter = timeSteps[0] / grid.speed
        var m = max(1, Int(chapter / preferredStep + 1e-9))
        var longest = chapter / Double(m)
        while m >= 1 {
            let step = chapter / Double(m)
            if step > maxStep { break }
            if totalSteps(grid, step) <= 128 { return step }
            longest = step
            m -= 1
        }
        throw Failure.tooLong(seconds: grid.rows.reduce(0) { $0 + $1.time } / grid.speed, limit: longest * 128)
    }

    static func rowSteps(_ grid: Grid, _ row: Row, _ step: Double) -> Int {
        max(1, Int((row.time / grid.speed / step).rounded(.toNearestOrEven)))
    }

    static func totalSteps(_ grid: Grid, _ step: Double) -> Int {
        grid.rows.reduce(0) { $0 + rowSteps(grid, $1, step) }
    }

    /// One value per lane step. A glide is a straight ramp from the previous row (the last one on a looping grid).
    static func laneSteps(_ grid: Grid, out: Int, step: Double) -> [Double] {
        var steps: [Double] = []
        var prev = grid.loop ? grid.rows.last?.values[out] ?? 0 : 0
        for row in grid.rows {
            let v = row.values[out]
            let n = rowSteps(grid, row, step)
            let g = out == gateOutput ? 0 : min(n, Int((row.glide / grid.speed / step).rounded(.toNearestOrEven)))
            for k in 0..<n { steps.append(k < g ? prev + (v - prev) * Double(k + 1) / Double(g) : v) }
            prev = v
        }
        return steps
    }

    /// A short note on seq 2 at the first step of each row whose trigger is on.
    static func writeTriggers(_ grid: Grid, step: Double, into d: inout [UInt8]) {
        var p = Array(d[trigPattern..<trigPattern + patternSize])
        var starts = Set<Int>(), k = 0
        for row in grid.rows {
            if row.trig == .start { starts.insert(k) }
            k += rowSteps(grid, row, step)
        }
        for i in 0..<128 {
            p[4 + i * monoRec] = starts.contains(i) ? note : 255
            p[4 + i * monoRec + 3] = trigLength
        }
        for (at, count) in monoEnds { for j in 0..<count { p[at + j] = UInt8(k - 1) } }
        p[monoLength] = UInt8(k)
        put(crc(p[0..<monoCRC]), into: &p, at: monoCRC)
        d.replaceSubrange(trigPattern..<trigPattern + patternSize, with: p)

        for j in 0..<16 { d[seqVoices + j] = j == 8 ? 0 : 255 }   // seq 2 voice 1 -> Gate 1
        d[gateSeq] = 2
        d[gateType] = 0
    }

    /// The STM32's hardware CRC-32: poly 0x04C11DB7, init 0xFFFFFFFF, over little-endian 32-bit words, no reflection.
    static func crc(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        var i = bytes.startIndex
        while i < bytes.endIndex {
            c ^= UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
            for _ in 0..<32 { c = c & 0x8000_0000 != 0 ? (c << 1) ^ 0x04C1_1DB7 : c << 1 }
            i += 4
        }
        return c
    }

    static func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        for j in 0..<4 { bytes[offset + j] = UInt8((value >> (8 * UInt32(j))) & 0xFF) }
    }

    /// oxi_projects/OXI-TEMPLATE.oxipro from the llm repo, raw-deflated (it is almost all zeros) and base64 encoded.
    static func template() -> Data {
        let packed = Data(base64Encoded: templateBase64.joined())!
        return try! (packed as NSData).decompressed(using: .zlib) as Data
    }

    static let templateBase64 = [
        "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"
    ]
}
