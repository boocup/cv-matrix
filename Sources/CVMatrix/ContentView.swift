import SwiftUI

private let numberFormat: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...2))

struct ContentView: View {
    @Bindable var store: MatrixStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("CV Matrix").font(.title2.bold())
                Spacer()
                HStack(spacing: 4) {
                    Text("Speed")
                    TextField("", value: speedBinding, format: numberFormat)
                        .frame(width: 60)
                    Text("(0.5 = twice as fast)").foregroundStyle(.secondary)
                }
                Toggle("Loop", isOn: $store.grid.loop)
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
                                onSelect: { store.selected = store.grid.rows.firstIndex(where: { $0.id == row.id }) ?? 0 },
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
        .onChange(of: store.grid) { _, _ in store.scheduleSave() }
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
            ForEach(1...outputs, id: \.self) { Text("Out \($0)").frame(width: 84) }
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
            TextField("", text: $row.name).frame(width: 150)
            TextField("", value: timeBinding, format: numberFormat).frame(width: 66)
            TextField("", value: glideBinding, format: numberFormat).frame(width: 66)
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
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25)))
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
