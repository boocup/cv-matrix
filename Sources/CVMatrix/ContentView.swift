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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    BrandMark()
                    Text("CV Matrix").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.label)
                }
                .padding(.trailing, 10)
                if generator.running {
                    ProgressView().controlSize(.small)
                    Text(generator.progress).foregroundStyle(.secondary)
                    Button("Cancel") { generator.cancel() }
                }
                Spacer(minLength: 16)
                Menu {
                    ForEach(Trig.allCases, id: \.self) { t in
                        Button(t.label) { store.setAllTrigs(t) }
                    }
                } label: { Label("Trigger All Rows", systemImage: "bolt") }
                .fixedSize()
                .help("Set Out 8's trigger on every row at once. New rows copy the row above.")
                Button { loadGrid() } label: { Label("Open…", systemImage: "doc") }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Load a grid file (⌘O)")
                Button { saveGrid() } label: { Label("Save…", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save a copy of the grid (⌘S)")
                Toggle("Autosave", isOn: $store.autosave).fixedSize()
                    .help("Write edits to matrix_grid.json as you make them")
                    .padding(.trailing, 4)
                Button { showPrompt = true } label: { Label("Generate…", systemImage: "sparkles") }
                    .disabled(generator.running)
                    .help("Ask Claude to write a new piece. Opens a window for your direction, then runs chapters.py from your ambient-agent folder with the Claude backend: a few cents per run, uses your ANTHROPIC_API_KEY. The new grid is loaded but not played.")
                Button { showGeneratedFolder() } label: { Label("Files", systemImage: "folder") }
                    .help("Show the grid files folder (~/Documents/CV Matrix) in Finder")
            }
            DisplayPanel(store: store, player: player)
            if !generator.error.isEmpty { Text(generator.error).foregroundStyle(.red) }
            if !player.message.isEmpty {
                Text(player.message).foregroundStyle(.red)
            }
            if !store.message.isEmpty {
                Text(store.message).foregroundStyle(Theme.label.opacity(0.8))
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
                    Button { store.addRow() } label: { Label("Add Chapter", systemImage: "plus") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.label)
                        .padding(.leading, 10).padding(.top, 2)
                }
                .padding(.bottom, 8)
            }

            Text("Drag a knob up or down, with Shift for fine steps; double-click for 0 V. Click a row number to play from it, or to jump there while playing. Time is the whole chapter; Glide is the part of it spent moving from the previous one. Knobs run −5 to +5 V.")
                .font(.system(size: 11)).foregroundStyle(Theme.label.opacity(0.6))
        }
        .padding(.horizontal, 18).padding(.bottom, 14).padding(.top, 2)
        .frame(minWidth: 1000, minHeight: 400)
        .background(
            Color.clear.contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }   // click empty space: leave the text field
        )
        .background(Theme.panel.ignoresSafeArea())
        .preferredColorScheme(.light)                                    // the panel look is light only
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
                                height: contentSize.height + (content.height - viewportSize.height) + 44)   // + room for text that rewraps
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
        panel.nameFieldStringValue = (store.gridName ?? "matrix_grid") + ".json"
        panel.message = "Save a copy of the grid"
        panel.directoryURL = MatrixStore.gridsDirForPanel()
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
        panel.message = "Choose a CV Matrix grid file (.json)"
        panel.directoryURL = MatrixStore.gridsDirForPanel()
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

    /// 0...1 for the row being played, nil for the others.
    private func progress(for id: Row.ID) -> Double? {
        guard player.playing, let i = store.grid.rows.firstIndex(where: { $0.id == id }), i == player.current,
              player.rowTime > 0 else { return nil }
        return min(1, player.elapsed / player.rowTime)
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 34, height: 1)
                columnTitle("Chapter").padding(.leading, 6).frame(width: 150, alignment: .leading)
                columnTitle("Time", unit: "sec").padding(.leading, 6).frame(width: 66, alignment: .leading)
                columnTitle("Glide", unit: "sec").padding(.leading, 6).frame(width: 66, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 4)
            .zone(Theme.red)
            outputHeaders(0..<4, color: Theme.blue).zone(Theme.blue)
            outputHeaders(4..<outputs, color: Theme.orange).zone(Theme.orange)
            Color.clear.frame(width: 58, height: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 6)
    }

    private func columnTitle(_ title: String, unit: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.label)
            if let unit { Text(unit).font(.system(size: 10)).foregroundStyle(Theme.label.opacity(0.55)) }
        }
        .fixedSize()
    }

    private func outputHeaders(_ range: Range<Int>, color: Color) -> some View {
        HStack(spacing: 6) {
            ForEach(range, id: \.self) { k in
                VStack(spacing: 3) {
                    HStack(spacing: 5) {
                        Text("\(k + 1)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(color.opacity(0.85)))
                            .help("ES-8 output \(k + 1)")
                        Text(outputNames[k]).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.label)
                    }
                    Text(String(format: "%+.2f V", player.volts[k]))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(abs(player.volts[k]) > 0.005 ? Theme.live : Theme.label.opacity(0.4))
                }
                .frame(width: 84)
            }
        }
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
            HStack(spacing: 6) {
                RowNumber(number: index + 1, selected: selected, playing: progress != nil, action: onSelect)
                ChapterName(name: $row.name, playing: progress != nil).frame(width: 150, alignment: .leading)
                TextField("", value: timeBinding, format: numberFormat).frame(width: 66).escapeLeavesField()
                    .monospacedDigit().help("Whole chapter, in seconds")
                TextField("", value: glideBinding, format: numberFormat).frame(width: 66).escapeLeavesField()
                    .monospacedDigit().help("Seconds spent gliding in from the previous chapter")
            }
            .frame(maxHeight: .infinity)
            .zone(Theme.red)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { k in KnobView(value: $row.values[k]) }
            }
            .zone(Theme.blue)
            HStack(spacing: 6) {
                intervalPicker($row.values[4])                  // Out 5 and 6 pick a pitch-shift interval
                intervalPicker($row.values[5])
                gatePicker($row.values[gateOutput])             // Out 7: gate
                TrigPicker(trig: $row.trig)                     // Out 8: trigger
            }
            .frame(maxHeight: .infinity)
            .zone(Theme.orange)
            HStack(spacing: 10) {
                Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }
                    .help("Duplicate chapter")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .help("Delete chapter")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13))
            .foregroundStyle(Theme.label.opacity(0.6))
            .frame(width: 58)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.row))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(progress != nil ? Theme.live : selected ? Color.accentColor : Color.black.opacity(0.15),
                    lineWidth: progress != nil || selected ? 1.5 : 1))
        .overlay(alignment: .bottomLeading) {
            if let progress {
                GeometryReader { g in
                    Rectangle().fill(Theme.live).frame(width: g.size.width * progress, height: 3)
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
        .fixedSize()
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

/// A chapter's name as display type (serif, like a title card). Double-click to rename; Return or Escape finishes.
struct ChapterName: View {
    @Binding var name: String
    let playing: Bool
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("Chapter name", text: $name)
                .focused($focused)
                .onSubmit { editing = false }
                .onExitCommand { editing = false }
                .onChange(of: focused) { _, f in if !f { editing = false } }
                .onAppear { focused = true }
        } else {
            Text(name.isEmpty ? "Untitled" : name)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(playing ? Theme.live : Theme.label)
                .lineLimit(2).minimumScaleFactor(0.8)
                .padding(.leading, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { editing = true }
                .help("Double-click to rename")
        }
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
