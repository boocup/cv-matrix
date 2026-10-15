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

/// Out 5 and 6: pick a pitch-shift interval (1 V/oct) instead of turning a knob. Stored as plain volts, so grid files
/// are unchanged. A value that is not one of the choices shows as Custom, with a box to type any voltage.
struct IntervalPicker: View {
    @Binding var value: Double
    @State private var forceCustom = false

    private static let choices: [(name: String, volts: Double)] = [
        ("None", 0), ("Major 3rd", 4.0 / 12), ("4th", 5.0 / 12), ("5th", 7.0 / 12), ("Octave", 1.0),
    ]

    private var selection: Int {
        if forceCustom { return -1 }
        return Self.choices.firstIndex { abs($0.volts - value) < 0.0005 } ?? -1
    }

    var body: some View {
        VStack(spacing: 2) {
            Picker("", selection: Binding(
                get: { selection },
                set: { i in
                    if i >= 0 { forceCustom = false; value = Self.choices[i].volts } else { forceCustom = true }
                })) {
                ForEach(Self.choices.indices, id: \.self) { Text(Self.choices[$0].name).tag($0) }
                Text("Custom").tag(-1)
            }
            .labelsHidden()
            .frame(width: 80)
            .help("Pitch shift at 1 V/oct. Custom lets you type any voltage.")

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
