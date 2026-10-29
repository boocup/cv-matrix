import SwiftUI

/// Colors for the outputs on the dark display: the four voices, the two pitch shifts, the gate and the trigger.
enum Voice {
    static let colors: [Color] = [
        Color(hex: 0xff7a6b),   // 1 Lead
        Color(hex: 0xf2b880),   // 2 Harmony
        Color(hex: 0x89a7e6),   // 3 Drone (the panel numeral blue)
        Color(hex: 0x8fd4a4),   // 4 Texture
        Color(hex: 0xc9a7f0),   // 5 Pitch
        Color(hex: 0xe6a7d8),   // 6 Pitch
        Color(hex: 0xffc857),   // 7 Gate
        Color.white,            // 8 Trigger
    ]
}

/// The whole piece as the player would run it from row 1: per-output voltage curves using the same glide rule as
/// Player.apply (one shared slew per row, so the largest change takes the glide and smaller ones arrive early),
/// plus where each row starts, where the gate is high and where triggers fire. Times include Speed.
struct PiecePlan {
    var starts: [Double] = []            // start time of each row
    var total = 0.0
    var curves: [[CGPoint]] = Array(repeating: [CGPoint(x: 0, y: 0)], count: 6)   // Out 1 to 6: (seconds, volts)
    var gates: [ClosedRange<Double>] = []
    var trigs: [Double] = []
    var low = 0.0, high = 1.0            // voltage range drawn

    init(_ grid: Grid) {
        var v = [Double](repeating: 0, count: 6)
        var t = 0.0
        for row in grid.rows {
            starts.append(t)
            let time = row.time * grid.speed, glide = row.glide * grid.speed
            let target = (0..<6).map { clamp(row.values[$0], -maxVolts, maxVolts) }
            let dist = (0..<6).map { abs(target[$0] - v[$0]) }.max() ?? 0
            let slew = dist > 0 ? clamp(dist / max(glide, 0.2), 0.05, 100) : 1
            for k in 0..<6 {
                let delta = target[k] - v[k]
                let moved = min(abs(delta), slew * time)
                let end = v[k] + (delta < 0 ? -moved : moved)
                curves[k].append(CGPoint(x: t + moved / slew, y: end))
                curves[k].append(CGPoint(x: t + time, y: end))
                v[k] = end
            }
            if row.values[gateOutput] > gateVolts / 2 { gates.append(t...(t + time)) }
            if row.trig == .start { trigs.append(t) }
            t += time
        }
        total = max(t, 1)
        let all = curves.flatMap { $0.map(\.y) }
        low = min(0, all.min() ?? 0)
        high = max(1, all.max() ?? 1)
    }

    /// Row playing at `t` seconds into the piece.
    func row(at t: Double) -> Int { max(0, (starts.lastIndex { $0 <= t }) ?? 0) }
}

/// The dark screen under the toolbar: transport, what is playing, the piece visualizer and live meters.
struct DisplayPanel: View {
    @Bindable var store: MatrixStore
    @Bindable var player: Player

    var body: some View {
        let plan = PiecePlan(store.grid)
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TransportButton(symbol: "play.fill", tint: Theme.live, active: player.playing,
                                    help: "Play from chapter \(store.selected + 1) (⌘Return)") {
                        player.play(from: store.selected)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(player.playing)
                    TransportButton(symbol: "stop.fill", tint: Color(white: 0.32), active: false,
                                    help: "Stop: every output glides to 0 V (⌘.)") { player.stop() }
                        .keyboardShortcut(".", modifiers: .command)
                    readout(plan)
                }
                HStack(spacing: 12) {
                    Picker("Speed", selection: speedChoice) {
                        Text("Half").tag(2.0)
                        Text("Normal").tag(1.0)
                        Text("Double").tag(0.5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                    .help("Playback speed: half speed, normal, or double speed")
                    Toggle("Loop", isOn: $store.grid.loop).fixedSize()
                    Toggle(isOn: $player.sendToES8) {
                        Text(player.sendToES8 ? "ES-8" : "Dry run")
                            .foregroundStyle(player.sendToES8 ? Theme.orangeOnDark : .secondary)
                            .frame(width: 52, alignment: .trailing)     // fixed, so the switch does not move
                    }
                    .toggleStyle(.switch).controlSize(.mini)
                    .disabled(player.playing)
                    .fixedSize()
                    .help(player.sendToES8 ? "Sending to the ES-8. Turn off for a dry run that sends nothing."
                                           : "Dry run: nothing is sent. Turn on to send to the ES-8.")
                }
                .font(.system(size: 12))
            }
            .frame(width: 380, alignment: .leading)

            PieceTimeline(plan: plan, player: player, selected: store.selected) { row in
                store.selected = row
                if player.playing { player.jump(to: row) } else { player.play(from: row) }
            }
            .frame(minWidth: 300, maxWidth: .infinity)

            Meters(volts: player.volts)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(height: 112)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(hex: 0x24201f), Color(hex: 0x141212)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
        .environment(\.colorScheme, .dark)
    }

    private var speedChoice: Binding<Double> {
        Binding(get: { store.grid.speed }, set: { store.grid.speed = $0 })
    }

    /// Chapter number, name and time: the playing row, or the selected one when stopped.
    private func readout(_ plan: PiecePlan) -> some View {
        let rows = store.grid.rows
        let i = player.playing ? player.current : store.selected
        let row = rows.indices.contains(i) ? rows[i] : nil
        let pieceAt = player.playing && plan.starts.indices.contains(i) ? plan.starts[i] + player.elapsed : 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(player.playing ? "PLAYING · CHAPTER \(i + 1) OF \(rows.count)" : "READY · CHAPTER \(i + 1) OF \(rows.count)")
                .font(.system(size: 9.5, weight: .semibold)).tracking(1.2)
                .foregroundStyle(player.playing ? Theme.liveOnDark : Color.white.opacity(0.45))
            Text(row?.name ?? "")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(player.playing
                 ? "\(clock(player.elapsed)) / \(clock(player.rowTime))   ·   \(clock(pieceAt)) / \(clock(plan.total))"
                 : "\(clock((row?.time ?? 0) * store.grid.speed)) chapter   ·   \(clock(plan.total)) piece")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func clock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// A round transport button: a glossy colored disc with a white symbol, and a soft glow while active.
struct TransportButton: View {
    let symbol: String
    let tint: Color
    let active: Bool
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(Color.white.opacity(hovering && enabled ? 0.45 : 0.18), lineWidth: 1)
                Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .shadow(color: active ? tint.opacity(0.8) : .black.opacity(0.4), radius: active ? 10 : 3, y: active ? 0 : 2)
            .opacity(enabled || active ? 1 : 0.45)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The piece drawn over time: one glowing curve per output (1 to 6), chapter dividers and numbers, gate bars, trigger
/// ticks, and a playhead. The part already played is bright; the rest is dimmed. Click to play from that chapter.
struct PieceTimeline: View {
    let plan: PiecePlan
    let player: Player
    let selected: Int
    let onPick: (Int) -> Void

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let top = 14.0, bottom = h - 6
            let x = { (t: Double) in t / plan.total * w }
            let y = { (v: Double) in bottom - (v - plan.low) / (plan.high - plan.low) * (bottom - top) }
            let head = player.playing && plan.starts.indices.contains(player.current)
                ? plan.starts[player.current] + player.elapsed : nil

            Canvas { ctx, size in
                // chapter bands, dividers and numbers
                for (i, s) in plan.starts.enumerated() {
                    let e = i + 1 < plan.starts.count ? plan.starts[i + 1] : plan.total
                    let band = CGRect(x: x(s), y: 0, width: x(e) - x(s), height: size.height)
                    let current = head != nil ? i == player.current : i == selected
                    if current { ctx.fill(Path(band), with: .color(.white.opacity(0.06))) }
                    if i > 0 {
                        ctx.stroke(Path { $0.move(to: CGPoint(x: band.minX, y: 0)); $0.addLine(to: CGPoint(x: band.minX, y: size.height)) },
                                   with: .color(.white.opacity(0.1)), lineWidth: 1)
                    }
                    if band.width > 14 {
                        ctx.draw(Text("\(i + 1)").font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .foregroundColor(.white.opacity(current ? 0.8 : 0.35)),
                                 at: CGPoint(x: band.minX + 4, y: 1), anchor: .topLeading)
                    }
                }
                // zero line
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y(0))); $0.addLine(to: CGPoint(x: size.width, y: y(0))) },
                           with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                // gate bars and trigger ticks
                for gate in plan.gates {
                    ctx.fill(Path(roundedRect: CGRect(x: x(gate.lowerBound), y: size.height - 3,
                                                      width: max(2, x(gate.upperBound) - x(gate.lowerBound)), height: 3), cornerRadius: 1.5),
                             with: .color(Voice.colors[gateOutput].opacity(0.75)))
                }
                for t in plan.trigs {
                    ctx.fill(Path(CGRect(x: x(t) - 0.75, y: top - 2, width: 1.5, height: 6)), with: .color(.white.opacity(0.7)))
                }
                // curves: dim everywhere, then bright with a glow up to the playhead
                let paths = plan.curves.map { pts in Path { p in
                    p.addLines(pts.map { CGPoint(x: x($0.x), y: y($0.y)) })
                } }
                for k in (0..<6).reversed() where plan.curves[k].contains(where: { abs($0.y) > 0.001 }) {
                    var fill = paths[k]
                    fill.addLine(to: CGPoint(x: size.width, y: y(0)))
                    fill.addLine(to: CGPoint(x: 0, y: y(0)))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .linearGradient(Gradient(colors: [Voice.colors[k].opacity(0.16), Voice.colors[k].opacity(0)]),
                                                         startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
                    ctx.stroke(paths[k], with: .color(Voice.colors[k].opacity(head == nil ? 0.85 : 0.35)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                if let head {
                    let px = x(head)
                    ctx.drawLayer { layer in
                        layer.clip(to: Path(CGRect(x: 0, y: 0, width: px, height: size.height)))
                        layer.drawLayer { glow in
                            glow.addFilter(.blur(radius: 3))
                            for k in 0..<6 where plan.curves[k].contains(where: { abs($0.y) > 0.001 }) {
                                glow.stroke(paths[k], with: .color(Voice.colors[k].opacity(0.9)), lineWidth: 3)
                            }
                        }
                        for k in 0..<6 where plan.curves[k].contains(where: { abs($0.y) > 0.001 }) {
                            layer.stroke(paths[k], with: .color(Voice.colors[k]),
                                         style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        }
                    }
                    // playhead with a dot on each moving voice at its live value
                    ctx.drawLayer { glow in
                        glow.addFilter(.blur(radius: 4))
                        glow.stroke(Path { $0.move(to: CGPoint(x: px, y: 0)); $0.addLine(to: CGPoint(x: px, y: size.height)) },
                                    with: .color(.white.opacity(0.7)), lineWidth: 3)
                    }
                    ctx.stroke(Path { $0.move(to: CGPoint(x: px, y: 0)); $0.addLine(to: CGPoint(x: px, y: size.height)) },
                               with: .color(.white), lineWidth: 1)
                    for k in 0..<6 where plan.curves[k].contains(where: { abs($0.y) > 0.001 }) {
                        let dot = CGRect(x: px - 3, y: y(player.volts[k]) - 3, width: 6, height: 6)
                        ctx.fill(Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)), with: .color(Voice.colors[k].opacity(0.3)))
                        ctx.fill(Path(ellipseIn: dot), with: .color(Voice.colors[k]))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
            .contentShape(Rectangle())
            .onTapGesture { p in onPick(plan.row(at: p.x / max(w, 1) * plan.total)) }
            .help("The whole piece: one line per output. Click a chapter to play from it.")
        }
    }
}

/// Live level meters for Out 1 to 6 (bipolar, from the 0 V line), a gate lamp and a trigger lamp.
struct Meters: View {
    let volts: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<6, id: \.self) { k in
                VStack(spacing: 3) {
                    GeometryReader { g in
                        let mid = g.size.height * 0.5
                        let len = min(1, abs(volts[k]) / maxVolts) * mid
                        ZStack(alignment: .top) {
                            Capsule().fill(Color.white.opacity(0.07))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Voice.colors[k])
                                .shadow(color: Voice.colors[k].opacity(0.8), radius: len > 1 ? 4 : 0)
                                .frame(height: max(len, 0))
                                .offset(y: volts[k] >= 0 ? mid - len : mid)
                            Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1).offset(y: mid)
                        }
                    }
                    .frame(width: 7)
                    Text("\(k + 1)").font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                }
            }
            VStack(spacing: 10) {
                lamp(on: volts[gateOutput] > gateVolts / 2, color: Voice.colors[gateOutput], label: "G")
                lamp(on: volts[trigOutput] > gateVolts / 2, color: .white, label: "T")
            }
            .padding(.leading, 6)
        }
        .frame(height: 86)
        .help("Live outputs: 1 to 6 as levels from 0 V, G is the gate (Out 7), T flashes on a trigger (Out 8)")
    }

    private func lamp(on: Bool, color: Color, label: String) -> some View {
        VStack(spacing: 3) {
            Circle()
                .fill(on ? color : Color.white.opacity(0.1))
                .frame(width: 11, height: 11)
                .shadow(color: on ? color : .clear, radius: 5)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
        }
    }
}
