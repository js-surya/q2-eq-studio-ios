// SPDX-License-Identifier: GPL-3.0-only
// The EQ tab: the graph, the bands, the preamp and balance, Bass and Treble, and what's worth a look.
import EQCore
import SwiftUI

struct EQView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.horizontalSizeClass) private var width
    @State private var showBass = false
    @State private var note: String?

    var body: some View {
        @Bindable var studio = studio
        VStack(spacing: 0) {
            // The graph pinned above the list: it stays in view while the bands scroll, and a pull on the
            // list moves the list alone.
            VStack(spacing: 6) {
                GraphView()
                    .frame(height: width == .regular ? 320 : 230)
                if studio.response.shown != nil { ShownBar().padding(.horizontal, 12) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(Color.groupedBackground)
        List(selection: $studio.selected) {
            Section {
            } footer: {
                #if os(macOS)
                Text("Drag a dot or the curve to move a band. Press on the 0 dB line to add one. The wheel on a dot changes its Q; elsewhere it zooms. Press ? for every key.")
                #else
                Text("Drag a dot or the curve to move a band. Pinch to change the picked band's width. Double-tap to add a band.")
                #endif
            }

            Section {
                if width == .regular {
                    BandTableHeader().selectionDisabled()
                }
                ForEach(Array(studio.preset.bands.enumerated()), id: \.element.id) { index, band in
                    Group {
                        if width == .regular { BandTableRow(index: index, band: band) } else { BandRow(index: index, band: band) }
                    }
                        .tag(band.id)
                        .swipeActions(edge: .leading) {
                            Button(band.on ? "Off" : "On", systemImage: band.on ? "speaker.slash" : "speaker.wave.2") {
                                studio.change { p in if let k = p.bands.firstIndex(where: { $0.id == band.id }) { p.bands[k].on.toggle() } }
                            }
                            .tint(.gray)
                        }
                }
                .onDelete { offsets in
                    let ids = offsets.map { studio.preset.bands[$0].id }
                    for id in ids { studio.deleteBand(id) }
                }
                .onMove { from, to in studio.change { $0.bands.move(fromOffsets: from, toOffset: to) } }

                Button("Add Band", systemImage: "plus.circle.fill") { studio.addBand() }
                    .disabled(studio.preset.bands.count >= EQ.maxBands)
                    .selectionDisabled()
            } header: {
                HStack {
                    Text("Bands")
                    Spacer()
                    Text("\(studio.preset.bands.count) of \(EQ.maxBands)").monospacedDigit()
                }
            }

            PreampSection()

            Section {
                DisclosureGroup("Bass and Treble", isExpanded: $showBass) {
                    ForEach(Knob.allCases, id: \.self) { knob in
                        KnobRow(knob: knob, note: $note)
                    }
                    Text("As Poweramp's knobs: a low shelf at 90 Hz, Q 0.8, and a high shelf at 10 kHz, Q 0.6, each a band of its own.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .selectionDisabled()
            }

            let warnings = studio.warnings
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.subheadline)
                    }
                }
                .selectionDisabled()
            }
        }
        .groupedList()
        }
        .navigationTitle(studio.preset.name.isEmpty ? "EQ" : studio.preset.name)
        .toolbar { EQToolbar() }
        .inspector(isPresented: Binding(get: { studio.selected != nil }, set: { if !$0 { studio.selected = nil } })) {
            BandEditor()
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .alert("Bass and Treble", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("OK") {}
        } message: {
            Text(note ?? "")
        }
    }
}

private struct BandRow: View {
    @Environment(Studio.self) private var studio
    let index: Int
    let band: Band

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(band.on ? BandColor.of(index) : Color.secondary.opacity(0.5), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Format.hertz(band.freq)).font(.body.weight(.semibold).monospacedDigit())
                    if let knob = Knob.of(band) {
                        Text(knob.title).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    }
                }
                Text("\(Format.typeName(band.type)) · \(Format.q(band.q))\(band.channel == .all ? "" : " · \(Format.channelName(band.channel))")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.dB(band.gain))
                .font(.body.monospacedDigit())
                .foregroundStyle(band.on ? (band.gain > 0 ? Color.primary : band.gain < 0 ? Color.primary : Color.secondary) : Color.secondary)
                .strikethrough(!band.on)
        }
        .opacity(band.on ? 1 : 0.6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(band.on ? "" : "Off")
    }
}

private struct PreampSection: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let p = studio.preset
        Section {
            Toggle("Auto Preamp", isOn: Binding(get: { p.auto }, set: { v in studio.change { $0.auto = v } }))
            if p.auto {
                LabeledContent("At \(studio.rate == 44100 ? "44.1" : String(Int(studio.rate / 1000))) kHz", value: Format.dB(studio.autoFigure))
                    .foregroundStyle(.secondary)
            } else {
                ValueSlider(title: "Preamp", value: p.preamp, range: -24...12, step: 0.1, format: { Format.dB($0) }) { v in
                    studio.change("preamp") { $0.preamp = v }
                }
            }
            ValueSlider(title: "Balance", value: p.balance, range: -EQ.balanceMax...EQ.balanceMax, step: 0.1,
                        format: balanceText) { v in studio.change("balance") { $0.balance = v } }
            Picker("Draw the curve at", selection: Binding(get: { studio.rate }, set: { studio.rate = $0 })) {
                ForEach(Studio.rates, id: \.self) { r in Text(r == 44100 ? "44.1 kHz" : "\(Int(r / 1000)) kHz").tag(r) }
            }
        } header: {
            Text("Output")
        } footer: {
            Text(p.auto ? "Auto works the preamp out on the Q2 for each song's rate, so loud music never clips." : "")
        }
        .selectionDisabled()
    }

    private func balanceText(_ v: Double) -> String {
        if abs(v) < 0.05 { return "Centre" }
        return v > 0 ? "Right \(Format.dB(-v).replacingOccurrences(of: " dB", with: "")) L" : "Left \(Format.dB(v).replacingOccurrences(of: " dB", with: "")) R"
    }
}

private struct KnobRow: View {
    @Environment(Studio.self) private var studio
    let knob: Knob
    @Binding var note: String?

    var body: some View {
        ValueSlider(title: knob.title, value: knob.gain(in: studio.preset), range: 0...Knob.maxGain, step: 0.5,
                    format: { Format.dB($0) }) { v in
            guard let next = knob.set(v, in: studio.preset) else {
                note = "The Q2 takes up to \(EQ.maxBands) bands, so \(knob.title) has no room. Delete a band first."
                return
            }
            studio.change("knob-\(knob.rawValue)") { $0 = next }
        }
    }
}

/// A slider with its value beside its title, as Settings shows one.
struct ValueSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let set: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                                  set: { set(($0 / step).rounded() * step) }), in: range)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EQToolbar: ToolbarContent {
    @Environment(Studio.self) private var studio
    @State private var pasteError: String?

    var body: some ToolbarContent {
        @Bindable var studio = studio
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Undo", systemImage: "arrow.uturn.backward") { studio.undo() }
                .disabled(!studio.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo", systemImage: "arrow.uturn.forward") { studio.redo() }
                .disabled(!studio.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Menu("More", systemImage: "ellipsis") {
                Toggle("Each Band's Curve", systemImage: "point.3.connected.trianglepath.dotted", isOn: $studio.showEachBand)
                let anyOn = studio.preset.bands.contains { $0.on }
                Button(anyOn ? "Turn Every Band Off" : "Turn Every Band On", systemImage: anyOn ? "speaker.slash" : "speaker.wave.2") {
                    studio.change { p in for k in p.bands.indices { p.bands[k].on = !anyOn } }
                }
                Divider()
                Button("Copy", systemImage: "doc.on.doc") { studio.copyEQ() }
                Button("Paste Preset", systemImage: "doc.on.clipboard") {
                    if let t = Clipboard.text() { studio.open(text: String(t.prefix(Poweramp.fileMax)), name: "", from: "from the clipboard") }
                }
                Toggle("Inspect", systemImage: "scope", isOn: $studio.inspect)
                ThemePicker().pickerStyle(.menu)
                Button("Keyboard and Mouse", systemImage: "keyboard") { studio.showKeys = true }
                Divider()
                Button("Start Over with 10 Flat Bands", systemImage: "arrow.counterclockwise", role: .destructive) {
                    studio.replace(with: .flat(name: studio.preset.name))
                }
            }
        }
        if studio.live.on {
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: Binding(get: { studio.eqOn }, set: { studio.setMode($0) })) {
                    Label(studio.eqOn ? "EQ On" : "EQ Off", systemImage: "power")
                }
                .toggleStyle(.button)
                .tint(studio.eqOn ? .accentColor : .secondary)
                .help("EQ on or off on the Q2")
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}

// MARK: The bands as a table, as the page's computer layout has them

private enum Column { static let num: CGFloat = 30, on: CGFloat = 44, type: CGFloat = 130, side: CGFloat = 120, value: CGFloat = 92 }

private struct BandTableHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("#").frame(width: Column.num)
            Text("On").frame(width: Column.on)
            Text("Type").frame(width: Column.type, alignment: .leading)
            Text("Side").frame(width: Column.side, alignment: .leading)
            Text("Hz").frame(width: Column.value, alignment: .trailing)
            Text("dB").frame(width: Column.value, alignment: .trailing)
            Text("Q").frame(width: Column.value, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// A band's row: each value typed in place (1.2k is 1200), stepped with ↑ and ↓ (Shift finer), Return
/// going down a row.
private struct BandTableRow: View {
    @Environment(Studio.self) private var studio
    let index: Int
    let band: Band

    var body: some View {
        let knob = Knob.of(band)
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(band.on ? BandColor.of(index) : Color.secondary.opacity(0.5), in: .circle)
                .frame(width: Column.num)
            Toggle("On", isOn: field(\.on, "on")).labelsHidden().frame(width: Column.on)
            Picker("Type", selection: field(\.type, "type")) {
                ForEach(FilterType.allCases, id: \.self) { Text(Format.typeName($0)) }
            }
            .labelsHidden().frame(width: Column.type).disabled(knob != nil)
            Picker("Side", selection: field(\.channel, "channel")) {
                ForEach(Channel.allCases, id: \.self) { Text(Format.channelName($0)) }
            }
            .labelsHidden().frame(width: Column.side).disabled(knob != nil)
            Cell(value: band.freq, digits: 2, range: EQ.freqMin...EQ.freqMax, step: { v, up, fine in v * pow(2, (up ? 1 : -1) * (fine ? 1.0 / 48 : 1.0 / 12)) },
                 set: { v in set("freq") { $0.freq = (v * 100).rounded() / 100 } }, row: index, column: 0)
                .disabled(knob != nil)
            Cell(value: band.gain, digits: 1, range: (knob != nil ? 0 : -EQ.gainMax)...(knob != nil ? Knob.maxGain : EQ.gainMax),
                 step: { v, up, fine in v + (up ? 1 : -1) * (fine ? 0.1 : 0.5) },
                 set: { v in set("gain") { $0.gain = (v * 100).rounded() / 100 } }, row: index, column: 1)
            Cell(value: band.q, digits: 2, range: EQ.qMin...EQ.qMax, step: { v, up, fine in v * pow(2, (up ? 1 : -1) / (fine ? 24 : 6)) },
                 set: { v in set("q") { $0.q = (v * 1000).rounded() / 1000 } }, row: index, column: 2)
                .disabled(knob != nil)
            if let knob { Text(knob.title).font(.caption.weight(.semibold)).foregroundStyle(.tint) }
            Spacer(minLength: 0)
        }
        .opacity(band.on ? 1 : 0.6)
    }

    private func set(_ name: String, _ edit: @escaping (inout Band) -> Void) {
        let id = band.id
        studio.change("\(name)-\(id)") { p in if let k = p.bands.firstIndex(where: { $0.id == id }) { edit(&p.bands[k]) } }
    }

    private func field<T>(_ key: WritableKeyPath<Band, T>, _ name: String) -> Binding<T> {
        Binding(get: { band[keyPath: key] }, set: { v in set(name) { $0[keyPath: key] = v } })
    }
}

/// Which cell has the keyboard: a row and a column.
struct CellFocus: Hashable { let row, column: Int }

private struct Cell: View {
    @Environment(Studio.self) private var studio
    let value: Double
    let digits: Int
    let range: ClosedRange<Double>
    let step: (Double, Bool, Bool) -> Double
    let set: (Double) -> Void
    let row, column: Int
    @State private var text = ""
    @FocusState private var focus: CellFocus?

    var body: some View {
        TextField("", text: $text)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .textFieldStyle(.roundedBorder)
            .frame(width: Column.value)
            .focused($focus, equals: CellFocus(row: row, column: column))
            .onAppear { text = shown }
            .onChange(of: value) { if focus == nil { text = shown } }
            .onSubmit {
                commit()
                // Return goes down a row, in the same column.
                if row + 1 < studio.preset.bands.count { studio.cellFocus = CellFocus(row: row + 1, column: column) }
            }
            .onChange(of: studio.cellFocus) { if studio.cellFocus == CellFocus(row: row, column: column) { focus = studio.cellFocus } }
            .onChange(of: focus) { if focus == nil { commit() } }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let v = min(max(step(value, press.key == .upArrow, press.modifiers.contains(.shift)), range.lowerBound), range.upperBound)
                set(v)
                text = decimal(v, digits)
                return .handled
            }
    }

    private var shown: String { decimal(value, digits) }

    private func commit() {
        var t = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: ".")
        var scale = 1.0
        if t.hasSuffix("k") { scale = 1000; t.removeLast() }
        guard let v = Double(t) else { text = shown; return }
        let clamped = min(max(v * scale, range.lowerBound), range.upperBound)
        if clamped != value { set(clamped) }
        text = decimal(clamped, digits)
    }
}

extension Color {
    /// The grouped list's own background, so the pinned graph sits on it.
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
