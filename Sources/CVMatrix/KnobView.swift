import SwiftUI
import AppKit

/// -5 to +5 V. Drag up/down (200 px for the full 10 V, 2000 with Shift); double-click = 0 V.
struct KnobView: View {
    @Binding var value: Double
    @State private var dragStart: Double?

    private var angle: Double { -135 + (value + maxVolts) / (2 * maxVolts) * 270 }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()                                         // black knob, as on the module panels
                    .fill(LinearGradient(colors: [Theme.knobTop, Theme.knobBottom], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1.5)
                Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 15)
                    .offset(y: -11)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 42, height: 42)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        let start = dragStart ?? value
                        dragStart = start
                        let per = NSEvent.modifierFlags.contains(.shift) ? 2000.0 : 200.0
                        let v = start - g.translation.height / per * 10
                        value = (clamp(v, -maxVolts, maxVolts) * 100).rounded() / 100
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { value = 0 }

            VoltReadout(value: value)
        }
        .frame(width: 84)
    }
}

/// The voltage under a control, e.g. "+2.25 V".
struct VoltReadout: View {
    let value: Double
    var body: some View {
        Text(String(format: "%+.2f V", value))
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.label.opacity(abs(value) < 0.005 ? 0.4 : 0.75))
    }
}

/// Out 5 and 6: a stepped knob with four positions, None, 3rd, 5th and Octave (1 V/oct), Out 5 upward and Out 6
/// downward. Drag up or down to step; double-click for None.
struct PitchKnob: View {
    @Binding var step: Int
    let down: Bool
    @State private var dragStart: Int?

    private func angle(_ i: Int) -> Double { -135 + Double(i) * 90 }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                ForEach(pitchSteps.indices, id: \.self) { i in      // a dot at each position, the current one lit
                    Circle()
                        .fill(i == step ? Theme.orange : Theme.label.opacity(0.3))
                        .frame(width: 4, height: 4)
                        .offset(y: -26)
                        .rotationEffect(.degrees(angle(i)))
                }
                Circle()
                    .fill(LinearGradient(colors: [Theme.knobTop, Theme.knobBottom], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1.5)
                    .frame(width: 42, height: 42)
                Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1).frame(width: 42, height: 42)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 15)
                    .offset(y: -11)
                    .rotationEffect(.degrees(angle(step)))
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: step)
            }
            .frame(width: 42, height: 42)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        let start = dragStart ?? step
                        dragStart = start
                        step = Int(clamp(Double(start) - (g.translation.height / 30).rounded(), 0, 3))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { step = 0 }
            .help("Pitch shift \(down ? "down" : "up"), 1 V/oct: " + pitchSteps.indices.map {
                "\(pitchNames[$0]) \(String(format: "%+.2f V", (down ? -1 : 1) * pitchSteps[$0]))"
            }.joined(separator: " · "))

            Text(step == 0 ? "None" : pitchNames[step] + (down ? " ↓" : " ↑"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.label.opacity(step == 0 ? 0.4 : 0.75))
        }
        .frame(width: 84)
    }
}

/// A three-way toggle switch, as on a module panel: the first of `names` at the bottom, the last at the top. Click a
/// position or drag the lever. Hovering shows a small window with what each position means (`values`, bottom first),
/// the current one marked.
struct ThreeWaySwitch: View {
    @Binding var position: Int
    let title: String
    let names: [String]
    let values: [String]
    @State private var hovering = false
    @State private var showValues = false

    private let slotHeight = 46.0

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 5)                // the slot in the panel
                    .fill(LinearGradient(colors: [Theme.knobBottom, Theme.knobTop], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                Lever()
                    .frame(width: 12, height: 14)
                    .offset(y: 2 + Double(2 - position) * (slotHeight - 18) / 2)
                    .animation(.spring(response: 0.18, dampingFraction: 0.7), value: position)
            }
            .frame(width: 16, height: slotHeight)

            VStack(alignment: .leading, spacing: 0) {             // the names beside the slot, the current one darker
                ForEach([2, 1, 0], id: \.self) { p in
                    Text(names[p])
                        .font(.system(size: 9, weight: p == position ? .bold : .medium))
                        .foregroundStyle(Theme.label.opacity(p == position ? 0.9 : 0.4))
                        .frame(height: slotHeight / 3)
                }
            }
            .frame(width: 44, alignment: .leading)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            position = 2 - Int(clamp(g.location.y / (slotHeight / 3), 0, 2.99))
        })
        .onHover { inside in
            hovering = inside
            if inside {
                Task { try? await Task.sleep(nanoseconds: 400_000_000); if hovering { showValues = true } }
            } else {
                showValues = false
            }
        }
        .popover(isPresented: $showValues, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                SwiftUI.Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    ForEach([2, 1, 0], id: \.self) { p in
                        GridRow {
                            Text(names[p]).font(.system(size: 12, weight: p == position ? .bold : .regular))
                            Text(values[p]).font(.system(size: 12, weight: p == position ? .bold : .regular).monospacedDigit())
                        }
                        .foregroundStyle(p == position ? Color.primary : Color.secondary)
                    }
                }
            }
            .padding(10)
        }
    }
}

/// An Off / On toggle switch that moves left and right, for Out 7's gate and Out 8's trigger. Click to flip, or drag.
struct OnOffSwitch: View {
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [Theme.knobBottom, Theme.knobTop], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 5).fill(Theme.orange.opacity(isOn ? 0.75 : 0)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                Lever()
                    .frame(width: 16, height: 14)
                    .offset(x: isOn ? 24 : 2)
            }
            .frame(width: 42, height: 18)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: isOn)
            HStack {                                            // Off under the left end, On under the right
                label("Off", lit: !isOn)
                Spacer()
                label("On", lit: isOn)
            }
            .frame(width: 50)
        }
        .frame(width: 84)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { g in
            isOn = g.translation.width > 4 ? true : g.translation.width < -4 ? false : !isOn
        })
        .help(help)
    }

    private func label(_ text: String, lit: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: lit ? .bold : .medium))
            .foregroundStyle(Theme.label.opacity(lit ? 0.9 : 0.4))
    }
}

/// The metal lever of a toggle switch.
private struct Lever: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(colors: [Color(hex: 0xf4f4f4), Color(hex: 0x9a9a9a)], startPoint: .top, endPoint: .bottom))
            .overlay(Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1))
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
    }
}
