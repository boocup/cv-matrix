import Foundation
import Observation

/// Step 2: play logic as a dry run. Nothing here touches audio; `volts` is a simulation of where the
/// outputs would be, using the same glide rules as the Python version (one shared slew per row).
@MainActor
@Observable
final class Player {
    private(set) var playing = false
    private(set) var current = -1        // row being played, -1 when stopped
    private(set) var elapsed = 0.0       // seconds into the current row
    private(set) var rowTime = 0.0       // length of the current row after speed
    private(set) var volts = [Double](repeating: 0, count: outputs)

    @ObservationIgnored private let store: MatrixStore
    @ObservationIgnored private var target = [Double](repeating: 0, count: outputs)
    @ObservationIgnored private var slew = 1.0            // V/s, shared by all outputs
    @ObservationIgnored private var index = 0
    @ObservationIgnored private var rowStart = 0.0
    @ObservationIgnored private var lastTick = 0.0
    @ObservationIgnored private var ticker: Task<Void, Never>?

    private static let tickSeconds = 0.05
    private static let stopSlew = 10.0                    // V/s back to 0 V, as es8.py close()

    init(store: MatrixStore) { self.store = store }

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }

    func play(from start: Int) {
        guard !playing else { return }
        index = Int(clamp(Double(start), 0, Double(store.grid.rows.count - 1)))
        playing = true
        startRow()
        startTicker()
    }

    func stop() {
        guard playing else { return }
        playing = false
        current = -1
        elapsed = 0
        rowTime = 0
        glideToZero()
    }

    private func glideToZero() {
        target = [Double](repeating: 0, count: outputs)
        slew = Self.stopSlew
    }

    private func startRow() {
        let grid = store.grid
        if index >= grid.rows.count {
            guard grid.loop else { stop(); return }
            index = 0
        }
        let row = grid.rows[index]
        current = index
        rowStart = now()
        elapsed = 0
        rowTime = row.time * grid.speed
        apply(row.values, glide: row.glide * grid.speed)
    }

    /// Same as Python _apply: the largest change takes `glide` seconds; smaller changes arrive early.
    private func apply(_ values: [Double], glide: Double) {
        target = values.map { clamp($0, -maxVolts, maxVolts) }
        let dist = zip(target, volts).map { abs($0 - $1) }.max() ?? 0
        slew = dist > 0 ? clamp(dist / max(glide, 0.2), 0.05, 100) : 1
    }

    private func startTicker() {
        guard ticker == nil else { return }
        lastTick = now()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.tickSeconds * 1e9))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let t = now()
        let dt = t - lastTick
        lastTick = t
        for k in 0..<outputs {
            let step = slew * dt
            volts[k] += max(-step, min(step, target[k] - volts[k]))
        }
        if playing {
            elapsed = t - rowStart
            if elapsed >= rowTime {
                index += 1
                startRow()
            }
        } else if volts.allSatisfy({ abs($0) < 1e-6 }) {
            ticker?.cancel()
            ticker = nil
        }
    }
}
