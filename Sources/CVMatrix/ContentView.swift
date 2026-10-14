import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let numberFormat: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...2))

struct ContentView: View {
    @Bindable var store: MatrixStore
    @Bindable var player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    BrandMark()
                    Text("CV Matrix").font(.title2.bold())
                }
                Button("▶ Play from row \(store.selected + 1)") { player.play(from: store.selected) }
                    .buttonStyle(.borderedProminent)
                    .disabled(player.playing)
                Button("■ Stop (glide to 0 V)") { player.stop() }
                Toggle("Send to ES-8", isOn: $player.sendToES8)
                    .disabled(player.playing)
                Spacer()
                Button("Load grid…", action: loadGrid)
                HStack(spacing: 4) {
                    Text("Speed")
                    TextField("", value: speedBinding, format: numberFormat)
                        .frame(width: 60)
                        .escapeLeavesField()
                    Text("(0.5 = twice as fast)").foregroundStyle(.secondary)
                }
                Toggle("Loop", isOn: $store.grid.loop)
            }
            Text((player.sendToES8 ? "Sending to the ES-8. " : "Dry run: nothing is sent. ") + statusText)
                .foregroundStyle(player.sendToES8 ? Color.orange : .secondary)
            if !player.message.isEmpty {
                Text(player.message).foregroundStyle(.red)
            }
            if !store.message.isEmpty {
                Text(store.message).foregroundStyle(.orange)
            }

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    ForEach($store.grid.rows) { $row in
                        RowView(row: $row,
                                index: store.grid.rows.firstIndex(where: { $0.id == row.id }) ?? 0,
                                selected: store.grid.rows.firstIndex(where: { $0.id == row.id }) == store.selected,
                                progress: progress(for: row.id),
                                onSelect: {
                                    let i = store.grid.rows.firstIndex(where: { $0.id == row.id }) ?? 0
                                    store.selected = i
                                    player.jump(to: i)
                                },
                                onDuplicate: { store.duplicate(row.id) },
                                onDelete: { store.delete(row.id) })
                    }
                    Button("+ Add row") { store.addRow() }
                }
                .padding(.bottom, 8)
            }

            Text("Drag a knob up or down (hold Shift for fine steps). Double-click a knob for 0 V. Click a row number to select it. Time is the whole row in seconds; glide is the part of it spent moving from the previous row. All knobs run -5 to +5 V.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 1000, minHeight: 400)
        .onChange(of: store.grid) { _, _ in
            store.scheduleSave()
            player.gridChanged()
        }
    }

    private func loadGrid() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a matrix_grid.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = "Replace the current grid with \(url.lastPathComponent)?"
        alert.informativeText = "The current grid is overwritten (it autosaves)."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        player.stop()
        do {
            try store.load(from: url)
        } catch {
            store.message = "could not load \(url.lastPathComponent): not a grid file"
        }
    }

    private var statusText: String {
        player.playing
            ? "Playing row \(player.current + 1) (\(Int(player.elapsed)) of \(Int(player.rowTime)) s)"
            : "Stopped."
    }

    /// 0...1 for the row being played, nil for the others.
    private func progress(for id: Row.ID) -> Double? {
        guard player.playing, let i = store.grid.rows.firstIndex(where: { $0.id == id }), i == player.current,
              player.rowTime > 0 else { return nil }
        return min(1, player.elapsed / player.rowTime)
    }

    private var speedBinding: Binding<Double> {
        Binding(get: { store.grid.speed },
                set: { store.grid.speed = clamp($0, 0.05, 20) })
    }

    private var header: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 34, height: 1)
            Text("Chapter").frame(width: 150, alignment: .leading)
            Text("Time s").frame(width: 66)
            Text("Glide s").frame(width: 66)
            ForEach(0..<outputs, id: \.self) { k in
                VStack(spacing: 0) {
                    Text("Out \(k + 1)")
                    Text(String(format: "%+.2f", player.volts[k])).monospacedDigit()
                        .foregroundStyle(Color.green)
                }
                .frame(width: 84)
            }
            Color.clear.frame(width: 58, height: 1)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}

struct RowView: View {
    @Binding var row: Row
    let index: Int
    let selected: Bool
    let progress: Double?
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 34)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
            TextField("", text: $row.name).frame(width: 150).escapeLeavesField()
            TextField("", value: timeBinding, format: numberFormat).frame(width: 66).escapeLeavesField()
            TextField("", value: glideBinding, format: numberFormat).frame(width: 66).escapeLeavesField()
            ForEach(0..<outputs, id: \.self) { k in
                KnobView(value: $row.values[k])
            }
            HStack(spacing: 4) {
                Button("⧉", action: onDuplicate).help("Duplicate")
                Button("✕", action: onDelete).help("Delete")
            }
            .frame(width: 58)
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(progress != nil ? Color.green : selected ? Color.accentColor : Color.secondary.opacity(0.25)))
        .overlay(alignment: .bottomLeading) {
            if let progress {
                GeometryReader { g in
                    Rectangle().fill(Color.green).frame(width: g.size.width * progress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var timeBinding: Binding<Double> {
        Binding(get: { row.time },
                set: { row.time = clamp($0, 1, 3600); row.glide = min(row.glide, row.time) })
    }

    private var glideBinding: Binding<Double> {
        Binding(get: { row.glide },
                set: { row.glide = clamp($0, 0, row.time) })
    }
}

/// THEREELPEET as on the module panels: the word in black (white in dark mode) with a red copy offset slightly
/// to the right and down. Offsets are the SVG's (1.3, 1.1 at 10.7 px) scaled to this size.
struct BrandMark: View {
    private let size = 15.0

    var body: some View {
        let word = Text("THEREELPEET").font(.system(size: size)).tracking(size * 0.22)
        ZStack(alignment: .topLeading) {
            word.foregroundStyle(.primary)
            word.foregroundStyle(Color(red: 1, green: 0, blue: 0))
                .offset(x: size * 0.12, y: size * 0.1)
        }
        .padding(.bottom, 2)
        .accessibilityLabel("THEREELPEET")
    }
}

extension View {
    /// Escape leaves a text field (what you typed is kept), so a stray click into one is easy to get out of.
    func escapeLeavesField() -> some View {
        onExitCommand { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
}
