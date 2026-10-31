import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: MatrixStore
    @Bindable var player: Player
    @State private var clearedInitialFocus = false
    @State private var window: NSWindow?
    @State private var closeGuard = CloseGuard()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    BrandMark()
                    Text("CV Matrix").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.label)
                }
                .padding(.trailing, 10)
                Spacer(minLength: 16)
                HStack(spacing: 6) {                                   // the file Save writes to, and whether it has edits
                    Image(systemName: "doc.text").foregroundStyle(Theme.label.opacity(0.5))
                    Text(store.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
                        .foregroundStyle(Theme.label.opacity(0.8))
                    if store.dirty { Text("Edited").foregroundStyle(Theme.label.opacity(0.45)) }
                }
                .font(.system(size: 12))
                .lineLimit(1)
                .help(store.fileURL?.path ?? "Not saved yet")
                .padding(.trailing, 6)
                Button { openGrid() } label: { Label("Open…", systemImage: "doc") }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Open a grid file (⌘O)")
                Button { store.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!store.dirty && store.fileURL != nil)
                    .help("Save to \(store.fileURL?.lastPathComponent ?? "a new file") (⌘S)")
                Button { store.saveAs() } label: { Label("Save As…", systemImage: "square.and.arrow.down.on.square") }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .help("Save under a new name (⇧⌘S)")
                Button { store.exportToOXI() } label: { Label("Export to OXI", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: .command)
                    .help("Write the grid as an OXI ONE project, Downloads/Projects/cvm.oxipro, for the OXI App (⌘E)")
            }
            DisplayPanel(store: store, player: player)
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

            Text("Drag a knob up or down, with Shift for fine steps; double-click for 0 V. Click a row number to play from it, or to jump there while playing. Time is the whole chapter (30, 60 or 120 s); Glide is the part of it spent moving from the previous one (¼, ⅓ or ½). Hover a switch for its values. Knobs run −5 to +5 V; the pitch knobs step through None, 3rd, 5th and Octave.")
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
        .background(WindowAccessor { w in
            window = w
            closeGuard.attach(to: w) { store.confirmDiscard() }
            if !clearedInitialFocus {                                  // AppKit gives the first text box (Speed) focus at launch
                clearedInitialFocus = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { w.makeFirstResponder(nil) }
            }
        })
        .onAppear { fitWindowSoon() }
        .onChange(of: store.grid) { _, _ in player.gridChanged() }
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

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }

    private func openGrid() {
        guard store.confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a CV Matrix grid file (.json)"
        panel.directoryURL = store.fileURL?.deletingLastPathComponent() ?? MatrixStore.gridsDirForPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        player.stop()
        do {
            try store.load(from: url)
            fitWindowSoon()
        } catch {
            store.message = "could not open \(url.lastPathComponent): not a grid file"
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
                columnTitle("Time").padding(.leading, 6).frame(width: 66, alignment: .leading)
                columnTitle("Glide").padding(.leading, 6).frame(width: 66, alignment: .leading)
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
                ThreeWaySwitch(position: $row.timeStep, title: "Time", names: timeNames,
                               values: timeSteps.map { seconds($0) }).frame(width: 66)
                ThreeWaySwitch(position: $row.glideStep, title: "Glide", names: glideNames,
                               values: glideDivisors.indices.map {
                                   "\(glideShareNames[$0])  ·  \(seconds(row.time / glideDivisors[$0]))"
                               }).frame(width: 66)
            }
            .frame(maxHeight: .infinity)
            .zone(Theme.red)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { k in KnobView(value: $row.values[k]) }
            }
            .zone(Theme.blue)
            HStack(spacing: 6) {
                PitchKnob(step: pitchStep(4), down: false)      // Out 5 and 6: pitch-shift intervals
                PitchKnob(step: pitchStep(5), down: true)
                OnOffSwitch(isOn: $row.gateOn,                  // Out 7: gate
                            help: "Gate: On is +5 V, held for the whole chapter. It snaps (no glide).")
                OnOffSwitch(isOn: Binding(get: { row.trig == .start }, set: { row.trig = $0 ? .start : .none }),
                            help: "Trigger: a 20 ms +5 V pulse at the start of the chapter.")   // Out 8
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

    private func pitchStep(_ k: Int) -> Binding<Int> {
        Binding(get: { row.pitchStep(k) }, set: { row.setPitchStep(k, $0) })
    }

    private func seconds(_ s: Double) -> String { String(format: s == s.rounded() ? "%.0f s" : "%.1f s", s) }
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

/// Asks before the window closes with unsaved edits. It stands in as the window's delegate and passes everything else
/// on to the delegate SwiftUI set.
final class CloseGuard: NSObject, NSWindowDelegate {
    private weak var original: NSWindowDelegate?
    private var shouldClose: () -> Bool = { true }

    func attach(to window: NSWindow, shouldClose: @escaping () -> Bool) {
        self.shouldClose = shouldClose
        guard window.delegate !== self else { return }
        original = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose() else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : nil
    }
}
