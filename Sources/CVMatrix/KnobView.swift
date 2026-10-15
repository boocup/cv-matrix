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
                Circle().fill(Color(nsColor: .windowBackgroundColor))
                Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 2)
                Capsule()
                    .fill(value < 0 ? Color(red: 0.42, green: 0.66, blue: 1) : Color(red: 0.88, green: 0.64, blue: 0.29))
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

            Text(String(format: "%+.2f V", value))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 84)
    }
}

/// A menu of fixed voltages in place of a knob. Stored as plain volts, so grid files are unchanged. A value that is not
/// one of the choices shows as Custom, with a box to type any voltage.
struct ChoicePicker: View {
    @Binding var value: Double
    let choices: [(name: String, volts: Double)]
    let help: String
    @State private var forceCustom = false

    private var selection: Int {
        if forceCustom { return -1 }
        return choices.firstIndex { abs($0.volts - value) < 0.0005 } ?? -1
    }

    var body: some View {
        VStack(spacing: 2) {
            Picker("", selection: Binding(
                get: { selection },
                set: { i in
                    if i >= 0 { forceCustom = false; value = choices[i].volts } else { forceCustom = true }
                })) {
                ForEach(choices.indices, id: \.self) { Text(choices[$0].name).tag($0) }
                Text("Custom").tag(-1)
            }
            .labelsHidden()
            .frame(width: 80)
            .help(help)

            ZStack {
                if selection == -1 {
                    TextField("V", value: Binding(get: { value }, set: { value = clamp($0, -maxVolts, maxVolts) }),
                              format: .number.precision(.fractionLength(0...3)))
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .escapeLeavesField()
                }
            }
            .frame(height: 18)

            Text(String(format: "%+.2f V", value))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 84)
    }
}

/// Out 5 and 6: pitch-shift intervals at 1 V/oct, upward.
func intervalPicker(_ value: Binding<Double>) -> some View {
    ChoicePicker(value: value,
                 choices: [("None", 0), ("Major 3rd", 4.0 / 12), ("4th", 5.0 / 12), ("5th", 7.0 / 12), ("Octave", 1.0)],
                 help: "Pitch shift at 1 V/oct. Custom lets you type any voltage.")
}

/// Out 7: a gate, held for the whole row. It snaps; it does not glide.
func gatePicker(_ value: Binding<Double>) -> some View {
    ChoicePicker(value: value, choices: [("Low", 0), ("High", gateVolts)],
                 help: "Gate: Low is 0 V, High is +5 V, held for the row. It snaps (no glide).")
}

/// Out 8: a +5 V pulse, 20 ms long, at the start of the row or when its glide has finished.
struct TrigPicker: View {
    @Binding var trig: Trig

    var body: some View {
        VStack(spacing: 2) {
            Picker("", selection: $trig) {
                ForEach(Trig.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 80)
            .help("Trigger: a 20 ms +5 V pulse at the start of the row, or when its glide has finished.")
            Color.clear.frame(height: 18)
            Text("trig").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(width: 84)
    }
}
