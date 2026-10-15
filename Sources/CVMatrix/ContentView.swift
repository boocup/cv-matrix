import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let numberFormat: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...2))

struct ContentView: View {
    @Bindable var store: MatrixStore
    @Bindable var player: Player
    @State private var generator = Generator()
    @AppStorage("generateChapters") private var generateChapters = 6
    @AppStorage("generateBrief") private var generateBrief = ""
    @AppStorage("generateVoices") private var generateVoices = 4
    @State private var showPrompt = false
    @State private var clearedInitialFocus = false
    @State private var window: NSWindow?

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
                Button("Save grid…", action: saveGrid)
                HStack(spacing: 4) {
                    Text("Speed")
                    TextField("", value: speedBinding, format: numberFormat)
                        .frame(width: 60)
                        .escapeLeavesField()
                    Text("(0.5 = twice as fast)").foregroundStyle(.secondary)
                }
                Toggle("Loop", isOn: $store.grid.loop)
                Toggle("Autosave", isOn: $store.autosave)
                    .help("Write edits to matrix_grid.json as you make them")
            }
            Text((player.sendToES8 ? "Sending to the ES-8. " : "Dry run: nothing is sent. ") + statusText)
                .foregroundStyle(player.sendToES8 ? Color.orange : .secondary)
            HStack(spacing: 10) {
                Button("✦ Generate with Claude…") { showPrompt = true }
                    .disabled(generator.running)
                    .help("Opens a window for your direction, then runs chapters.py from your ambient-agent folder with the Claude backend: a few cents per run, uses your ANTHROPIC_API_KEY. The new grid is loaded but not played.")
                Button("Show generated files") { showGeneratedFolder() }
                    .help("Opens the folder where Generate with Claude saves its grids, in Finder")
                if generator.running {
                    ProgressView().controlSize(.small)
                    Text(generator.progress).foregroundStyle(.secondary)
                    Button("Cancel") { generator.cancel() }
                }
                if !generator.error.isEmpty { Text(generator.error).foregroundStyle(.red) }
            }
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
                                    if player.playing { player.jump(to: i) } else { player.play(from: i) }
                                },
                                onDuplicate: { store.duplicate(row.id) },
                                onDelete: { store.delete(row.id) })
                    }
                    Button("+ Add row") { store.addRow() }
                }
                .padding(.bottom, 8)
            }

            Text("Drag a knob up or down (hold Shift for fine steps). Double-click a knob for 0 V. Click a row number to play from that row (or jump to it while playing). Time is the whole row in seconds; glide is the part of it spent moving from the previous row. All knobs run -5 to +5 V.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 1000, minHeight: 400)
        .background(
            Color.clear.contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }   // click empty space: leave the text field
        )
        .sheet(isPresented: $showPrompt) {
            PromptSheet(brief: $generateBrief, voices: $generateVoices, chapters: $generateChapters) {
                showPrompt = false
                generate()
            }
        }
        .background(WindowAccessor { w in
            window = w
            if !clearedInitialFocus {                                  // AppKit gives the first text box (Speed) focus at launch
                clearedInitialFocus = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { w.makeFirstResponder(nil) }
            }
        })
        .onAppear { fitWindowSoon() }
        .onChange(of: store.autosave) { _, on in if on { store.scheduleSave() } }
        .onChange(of: store.grid) { _, _ in
            store.scheduleSave()
            player.gridChanged()
        }
    }

    /// Size the window to show every row (as far as the screen allows). Runs on open and after loading a grid.
    private func fitWindowSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)   // let the first layout happen
            guard let window, let screen = window.screen ?? NSScreen.main, let root = window.contentView,
                  let scroll = Self.findScrollView(in: root), let document = scroll.documentView else { return }
            let contentSize = document.frame.size       // all rows, as laid out
            let viewportSize = scroll.contentSize       // the part of the window the rows are shown in
            let content = window.contentLayoutRect.size
            let wanted = NSSize(width: contentSize.width + (content.width - viewportSize.width),
                                height: contentSize.height + (content.height - viewportSize.height))
            let room = screen.visibleFrame.size
            var frame = window.frame
            let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: wanted)).size
            frame.size = NSSize(width: min(max(target.width, 1000), room.width), height: min(target.height, room.height))
            frame.origin.y = window.frame.maxY - frame.height                  // keep the top edge where it is
            window.setFrame(window.constrainFrameRect(frame, to: screen), display: true, animate: false)
        }
    }

    private func saveGrid() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "matrix_grid.json"
        panel.message = "Save a copy of the grid"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.save(to: url)
            store.message = ""
        } catch {
            store.message = "could not save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }

    private func showGeneratedFolder() {
        try? FileManager.default.createDirectory(at: MatrixStore.generatedDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(MatrixStore.generatedDir)
    }

    private func generate() {
        if !store.agentFolderValid && !store.chooseAgentFolder() { return }
        generator.start(chapters: generateChapters, voices: generateVoices, brief: generateBrief, agentFolder: store.agentFolder, outputDir: MatrixStore.generatedDir) { url in
            receiveGenerated(url)
        }
    }

    /// A new grid arrived. Loading stops playback and replaces the grid, so ask first if either would lose something.
    private func receiveGenerated(_ url: URL) {
        if player.playing || store.dirty {
            let alert = NSAlert()
            alert.messageText = "Claude's new piece is ready: \(url.deletingPathExtension().lastPathComponent)"
            alert.informativeText = (player.playing ? "Loading it stops the music now playing. " : "")
                + (store.dirty ? "Your current grid has edits that are not saved. " : "")
                + "The new piece is saved in \(MatrixStore.generatedDir.path) either way."
            alert.addButton(withTitle: "Load now")
            alert.addButton(withTitle: "Keep current grid")
            guard alert.runModal() == .alertFirstButtonReturn else {
                store.message = "New piece saved as \(url.lastPathComponent); use Load grid… to open it."
                return
            }
        }
        player.stop()
        do {
            try store.load(from: url)
            store.message = "Loaded \(url.lastPathComponent) from Claude. Press Play when you are ready."
            fitWindowSoon()
        } catch {
            store.message = "could not load \(url.lastPathComponent): \(error.localizedDescription)"
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
            fitWindowSoon()
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
            RowNumber(number: index + 1, selected: selected, playing: progress != nil, action: onSelect)
            TextField("", text: $row.name).frame(width: 150).escapeLeavesField()
            TextField("", value: timeBinding, format: numberFormat).frame(width: 66).escapeLeavesField()
            TextField("", value: glideBinding, format: numberFormat).frame(width: 66).escapeLeavesField()
            ForEach(0..<outputs, id: \.self) { k in
                if k == 4 || k == 5 {                        // Out 5 and 6 pick a pitch-shift interval
                    intervalPicker($row.values[k])
                } else if k == gateOutput {                  // Out 7: gate
                    gatePicker($row.values[k])
                } else if k == trigOutput {                  // Out 8: trigger
                    TrigPicker(trig: $row.trig)
                } else {
                    KnobView(value: $row.values[k])
                }
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

/// Hands the hosting NSWindow to SwiftUI.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { onWindow(w) } }
    }
}

/// The row number as a button: a round badge that shows a play triangle and the pointing-hand cursor on hover.
struct RowNumber: View {
    let number: Int
    let selected: Bool
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle().fill(playing ? Color.green : hovering ? Color.accentColor : Color.secondary.opacity(0.18))
            Circle().strokeBorder(selected && !playing ? Color.accentColor : .clear, lineWidth: 2)
            if hovering || playing {
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            } else {
                Text("\(number)").font(.body.weight(.semibold)).foregroundStyle(selected ? Color.accentColor : .primary)
            }
        }
        .frame(width: 28, height: 28)
        .frame(width: 34)
        .contentShape(Circle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture(perform: action)
        .help("Play from row \(number)")
        .accessibilityLabel("Play from row \(number)")
        .accessibilityAddTraits(.isButton)
    }
}

/// The window that asks what to tell Claude before a piece is generated.
struct PromptSheet: View {
    @Binding var brief: String
    @Binding var voices: Int
    @Binding var chapters: Int
    let onGenerate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate with Claude").font(.title3.bold())
            Text("Describe your voices and what you want, in your own words. Leave it empty for the built-in four-voice setup. Voice 1 goes to Out 1, voice 2 to Out 2, and so on; unused outputs stay at 0 V.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $brief)
                .font(.body)
                .frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
            Text("For example: Voice 1 and 2 are similar, voice 2 repeats note one. Voice 3 is a tape delay loop of voice 1 with overdub. Sparse and dark please.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Stepper("Voices: \(voices)", value: $voices, in: 1...8)
                Stepper("Chapters: \(chapters)", value: $chapters, in: 1...12)
            }
            Text("One Claude request per chapter, a few cents in total. The piece is loaded when it is ready, and not played.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Generate", action: onGenerate).keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}
