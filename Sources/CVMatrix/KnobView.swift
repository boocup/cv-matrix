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
