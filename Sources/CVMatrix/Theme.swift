import SwiftUI

/// The THEREELPEET panel look, from res/TheReelPeet*.svg in thereelpeet-dyn: a grey metal gradient with translucent
/// red, blue and orange sections, black knobs with a white pointer, and dark red-brown labels. Light only, like the panels.
enum Theme {
    static let panelTop = Color(hex: 0xd0d0d0)
    static let panelBottom = Color(hex: 0xb8b8b8)
    static let panel = LinearGradient(colors: [panelTop, panelBottom], startPoint: .top, endPoint: .bottom)

    static let red = Color(hex: 0xd94a4a)       // chapter, time, glide: how the piece moves
    static let blue = Color(hex: 0x4a78d9)      // Out 1 to 4: the CV voices
    static let orange = Color(hex: 0xd9824a)    // Out 5 to 8: pitch, gate, trig
    static let zoneOpacity = 0.18

    static let label = Color(hex: 0x280b0b)
    static let live = Color(red: 0.08, green: 0.48, blue: 0.16)   // green readable on the grey
    static let row = Color.white.opacity(0.35)

    static let knobTop = Color(hex: 0x3a3a3a)
    static let knobBottom = Color(hex: 0x0e0e0e)

    /// Zone of output column k.
    static func zone(forOutput k: Int) -> Color { k < 4 ? blue : orange }
}

/// Column names for the eight ES-8 outputs.
let outputNames = ["Lead", "Harmony", "Drone", "Texture", "Pitch", "Pitch", "Gate", "Trigger"]

/// Where the outputs go and whether it is playing: a dot and a short line of text in a capsule.
struct StatusPill: View {
    let live: Bool
    let playing: Bool
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(playing ? Theme.live : live ? Theme.orange : Theme.label.opacity(0.35))
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.label.opacity(0.85))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.45)))
        .overlay(Capsule().stroke(Color.black.opacity(0.08)))
        .help(live ? "Outputs go to the ES-8" : "Dry run: nothing is sent; turn on Send to ES-8")
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

extension View {
    /// A translucent rounded section, like the colored areas on the module panels.
    func zone(_ color: Color) -> some View {
        padding(.horizontal, 4).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(Theme.zoneOpacity)))
    }
}
