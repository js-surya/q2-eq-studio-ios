// SPDX-License-Identifier: GPL-3.0-only
// The EQ tab: the graph, the bands, the preamp and balance, Bass and Treble, and what's worth a look.
import EQCore
import SwiftUI

struct EQView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.horizontalSizeClass) private var width
    @AppStorage("eq.fold.bands") private var showBands = true
    @AppStorage("eq.fold.knobs") private var showKnobs = true
    @State private var note: String?
    @State private var height: CGFloat = 0

    /// 320 on an iPad, less when the window is short; 230 on an iPhone.
    private var graphHeight: CGFloat {
        // One height on an iPhone, a band picked or not: a touch on a dot picks its band, and a graph that
        // shrank then would move its scale under the finger mid-drag.
        guard width == .regular else { return 210 }
        return height > 0 ? min(320, max(200, height * 0.32)) : 320
    }

    var body: some View {
        GeometryReader { geo in
            // An iPhone Duo's inner display: nothing that takes a touch on the fold, as Apple's guidelines ask.
            // A fold top to bottom splits the tab in two, the graph and its band on one side, the bands on
            // the other; one across puts the graph above it and the bands below. An iPad on its side splits
            // the same way, so the graph takes the screen's height rather than a third of it. Elsewhere, one
            // column.
            if let split = Self.fold(geo).flatMap({ $0.height > $0.width ? $0 : nil }) ?? sideways(geo) {
                HStack(spacing: 0) {
                    // The graph and its tools on one side, the graph the whole height and never resized: the
                    // picked band's card (an iPhone's) heads the other side, over the bands, so a drag that
                    // picks a band doesn't shrink the graph under the finger.
                    header(fill: true, room: 76, card: false).frame(width: split.minX).clipped()
                    Color.clear.frame(width: split.width)
                    VStack(spacing: 0) {
                        BandStrip().padding(.horizontal, 12).padding(.top, 8).environment(\.horizontalSizeClass, .compact)
                        list(table: false) // the rest of the width: rows, not the table
                    }
                }
                .background(Color.groupedBackground)
            } else if let fold = Self.fold(geo) {
                VStack(spacing: 0) {
                    // Above the fold the graph and its tools, the graph its whole height; under it the
                    // band's card (an iPhone's) over the bands
                    header(fill: true, card: false).frame(height: fold.minY).clipped()
                    Color.clear.frame(height: fold.height)
                    BandStrip().padding(.horizontal, 12).padding(.top, 8).environment(\.horizontalSizeClass, .compact)
                    list(table: geo.size.width >= Self.tableWidth)
                }
                .background(Color.groupedBackground)
            } else {
                VStack(spacing: 0) {
                    header()
                    list(table: width == .regular && geo.size.width >= Self.tableWidth)
                }
            }
        }
        // The graph gives way on a short window (an iPad mini on its side), so the bands keep room.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .navigationTitle("EQ Studio")
        .settingsButton()
        .toolbar { EQToolbar() }
        .alert("Bass and Treble", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("OK") {}
        } message: {
            Text(note ?? "")
        }
    }

    /// The graph pinned above the list: it stays in view while the bands scroll, and a pull on the list moves
    /// the list alone.
    /// fill: a pane of its own by the fold, where the graph takes the height the rest leaves; room: what it
    /// leaves at its foot (the live status floats over a pane beside the fold).
    /// card: the picked band's card under the tools (else it goes under the fold, over the bands).
    private func header(fill: Bool = false, room: CGFloat = 8, card: Bool = true) -> some View {
        VStack(spacing: 6) {
            if !studio.outline.name.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "slider.vertical.3").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                    Marquee(text: studio.outline.name, detail: studio.sources[studio.outline.name])
                }
                .padding(.horizontal, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Playing \(studio.outline.name)\(studio.sources[studio.outline.name].map { ", from \($0)" } ?? "")")
            }
            GraphView()
                .frame(minHeight: fill ? 140 : graphHeight, maxHeight: fill ? .infinity : graphHeight)
            if studio.response.shown != nil { ShownBar().padding(.horizontal, 12) }
            ToolStrip()
            // The picked band under the graph, on an iPhone as on an iPad.
            if card { BandStrip().padding(.horizontal, width == .regular ? 8 : 0).padding(.top, 4) }
            if fill { Spacer(minLength: 0) } // only past the graph's least height
        }
        .padding(.horizontal, 12)
        .padding(.bottom, room)
        .background(Color.groupedBackground)
    }

    /// The bands and the rest; a table where it's wide enough, rows in a narrow pane.
    private func list(table: Bool) -> some View {
        @Bindable var studio = studio
        return List(selection: $studio.selected) {
        Section {
          if showBands {
            if table {
                BandTableHeader().selectionDisabled()
            }
            BandRows(table: table)

            Button("Add Band", systemImage: "plus.circle.fill") { studio.addBand() }
                .disabled(studio.outline.bandCount >= EQ.maxBands)
                .selectionDisabled()
          }
        } header: {
            Fold(title: "Bands", open: $showBands) {
                Text("\(studio.outline.bandCount) of \(EQ.maxBands)").monospacedDigit()
            }
        } footer: {
            if showBands {
                Text(studio.graphEdit
                     ? "Drag a dot or the curve to move a band. Double-tap to add a band. Touch and hold to read the curve."
                     : "The graph is locked, so a touch there won't move the curve: tap its pencil to drag and double-tap there. Touch and hold to read it.")
            }
        }

        Section {
            if showKnobs {
                ForEach(Knob.allCases, id: \.self) { knob in
                    KnobRow(knob: knob, note: $note)
                }
                .selectionDisabled()
            }
        } header: {
            Fold(title: "Bass and Treble", open: $showKnobs) {
                let b = studio.outline.bass, t = studio.outline.treble
                if !showKnobs && (b != 0 || t != 0) {
                    Text("\(Format.dB(b, digits: 1)) · \(Format.dB(t, digits: 1))").monospacedDigit()
                }
            }
        } footer: {
            if showKnobs {
                Text("As Poweramp's knobs: a low shelf at 90 Hz, Q 0.8, and a high shelf at 10 kHz, Q 0.6, each a band of its own.")
            }
        }

        PreampSection()

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
    // Room under the last row, so it scrolls clear of the tab bar and the live status.
    .contentMargins(.bottom, 120, for: .scrollContent)
    }

    /// Where a wide screen on its side (an iPad's, an unfolded Duo's without a fold reported) splits: the graph's
    /// side three fifths of it, a gap after it; nil upright or narrow.
    private func sideways(_ g: GeometryProxy) -> CGRect? {
        guard width == .regular, g.size.width > g.size.height * 1.15, g.size.width >= 900 else { return nil }
        return CGRect(x: (g.size.width * 0.58).rounded(), y: 0, width: 16, height: g.size.height)
    }

    /// The least width the bands' table fits in (its columns at their least, the list's insets); narrower, rows.
    static let tableWidth: CGFloat = 720

    /// Where a fold crosses this view, when it does (iPhone Duo's inner display, iOS 27.1): a division well
    /// inside it, never one at an edge.
    private static func fold(_ g: GeometryProxy) -> CGRect? {
        if #available(iOS 27.1, *) {
            let size = g.size
            return g.reservedRegions(kind: .division, options: .includeInactive).map(\.frame).first { f in
                f.height > f.width ? f.minX > 140 && f.maxX < size.width - 140 : f.minY > 200 && f.maxY < size.height - 200
            }
        }
        return nil
    }
}

/// The bands' rows, on their own: these alone read every band, so a drag redraws them and the dragged
/// row, not the screen around them (its toolbar, the tab bar's status).
private struct BandRows: View {
    @Environment(Studio.self) private var studio
    let table: Bool

    var body: some View {
        ForEach(Array(studio.preset.bands.enumerated()), id: \.element.id) { index, band in
            Group {
                if table { BandTableRow(index: index, band: band) } else { BandRow(index: index, band: band) }
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
                .background(BandColor.of(band), in: .circle)
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
    @AppStorage("eq.fold.output") private var open = true

    var body: some View {
        let p = studio.outline
        Section {
          if open {
            Toggle("Auto Preamp", isOn: Binding(get: { p.auto }, set: { v in studio.change { $0.auto = v } }))
            if p.auto {
                AutoFigure()
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
          }
        } header: {
            Fold(title: "Output", open: $open) {
                if !open { Text(p.auto ? "Auto" : Format.dB(p.preamp)).monospacedDigit() }
            }
        } footer: {
            if open { Text(p.auto ? "Auto works the preamp out on the Q2 for each song's rate, so loud music never clips." : "") }
        }
        .selectionDisabled()
    }

    private func balanceText(_ v: Double) -> String {
        if abs(v) < 0.05 { return "Centre" }
        return v > 0 ? "Right \(Format.dB(-v).replacingOccurrences(of: " dB", with: "")) L" : "Left \(Format.dB(v).replacingOccurrences(of: " dB", with: "")) R"
    }
}

/// Auto's preamp, which most drags move: on its own, so only this line is drawn again.
private struct AutoFigure: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        LabeledContent("At \(studio.rate == 44100 ? "44.1" : String(Int(studio.rate / 1000))) kHz", value: Format.dB(studio.autoFigure))
            .foregroundStyle(.secondary)
    }
}

private struct KnobRow: View {
    @Environment(Studio.self) private var studio
    let knob: Knob
    @Binding var note: String?

    var body: some View {
        ValueSlider(title: knob.title, value: studio.outline.gain(knob), range: 0...Knob.maxGain, step: 0.5,
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
        // A tick each whole dB, a bump at the centre (0).
        .sensoryFeedback(trigger: Int(value.rounded(.towardZero))) { old, new in
            new == 0 && old != 0 ? .impact(weight: .medium, intensity: 0.8) : .selection
        }
    }
}

private struct EQToolbar: ToolbarContent {
    @Environment(Studio.self) private var studio
    @State private var pasteError: String?

    var body: some ToolbarContent {
        @Bindable var studio = studio
        // Undo and redo are on the graph (GraphView's UndoButtons).
        if studio.live.on {
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: Binding(get: { studio.eqOn }, set: { studio.setMode($0) })) {
                    Label(studio.eqOn ? "EQ On" : "EQ Off", systemImage: "power")
                }
                .toggleStyle(.button)
                .tint(studio.eqOn ? studio.accent : .secondary)
                .help("EQ on or off on the Q2")
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}

// MARK: The bands as a table, as the page's computer layout has them

private enum Column { static let num: CGFloat = 30, on: CGFloat = 44, type: CGFloat = 130, side: CGFloat = 120, value: CGFloat = 92, valueMax: CGFloat = 170, knob: CGFloat = 56 }

private struct BandTableHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("#").frame(width: Column.num)
            Text("On").frame(width: Column.on)
            Text("Type").frame(width: Column.type, alignment: .leading)
            Text("Side").frame(width: Column.side, alignment: .leading)
            // The values share what's left of the width, so the table reaches the edge.
            Text("Hz").frame(minWidth: Column.value, maxWidth: Column.valueMax, alignment: .trailing)
            Text("dB").frame(minWidth: Column.value, maxWidth: Column.valueMax, alignment: .trailing)
            Text("Q").frame(minWidth: Column.value, maxWidth: Column.valueMax, alignment: .trailing)
            Color.clear.frame(width: Column.knob, height: 1)
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
                .background(BandColor.of(band), in: .circle)
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
            Text(knob?.title ?? "").font(.caption.weight(.semibold)).foregroundStyle(.tint)
                .frame(width: Column.knob, alignment: .leading)
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
            .frame(minWidth: Column.value, maxWidth: Column.valueMax)
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
        Color(uiColor: .systemGroupedBackground)
    }

    static var rowBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }
}

/// The graph's tools, in sight under it rather than in a menu: each band's curve, every band off or on,
/// Copy, Paste and Start Over.
private struct ToolStrip: View {
    @Environment(Studio.self) private var studio
    @State private var confirmReset = false

    var body: some View {
        @Bindable var studio = studio
        let allOff = studio.outline.allOff
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Tool(title: "Bands", icon: "point.3.connected.trianglepath.dotted", on: studio.showEachBand) { studio.showEachBand.toggle() }
                    .help("Each band's own curve")
                Tool(title: allOff ? "Bypassed" : "Bypass", icon: allOff ? "speaker.slash.fill" : "speaker.slash", on: allOff) {
                    studio.change { p in for k in p.bands.indices { p.bands[k].on = allOff } }
                }
                .help("Every band off, or on")
                Tool(title: "Copy", icon: "doc.on.doc", on: false) { studio.copyEQ() }
                    .help("The EQ as a preset's text")
                Tool(title: "Paste", icon: "doc.on.clipboard", on: false) { studio.pasteAsked = true }
                    .help("Paste an EQ: a preset's text or Poweramp's, from the clipboard or typed")
                Tool(title: "Reset", icon: "arrow.counterclockwise", on: false) { confirmReset = true }
                    .help("Start over with 10 flat bands")
            }
            .padding(.horizontal, 4)
        }
        .confirmationDialog("Start over with 10 flat bands?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Start Over", role: .destructive) {
                studio.replace(with: .flat(name: studio.preset.name))
                studio.say("10 flat bands. Undo brings back the EQ before.", undo: true)
            }
        }
    }
}

/// A tool: an icon and its word in a glass capsule, tinted while it's on.
private struct Tool: View {
    @Environment(Studio.self) private var studio
    let title: String
    let icon: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .glassEffect(on ? .regular.tint(studio.accent).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A line of text that fits, or, when it doesn't, scrolls to show the rest, waits, and scrolls back; the
/// edges faded. With Reduce Motion it stands still, cut short with an ellipsis.
struct Marquee: View {
    let text: String
    /// After the name, quieter: whose measurement it came from.
    var detail: String? = nil
    var font: Font = .headline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var full: CGFloat = 0
    @State private var room: CGFloat = 0
    @State private var start = Date()

    private let speed: CGFloat = 30 // points a second
    private let rest: Double = 1.6 // seconds still at each end

    private var line: Text {
        guard let detail, !detail.isEmpty else { return Text(text) }
        return Text("\(Text(text)) \(Text("– \(detail)").fontWeight(.regular).foregroundStyle(Color.secondary))")
    }

    var body: some View {
        let over = max(full - room, 0)
        line
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(over > 0 && !reduceMotion ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
            .overlay(alignment: .leading) {
                if over > 0 && !reduceMotion {
                    TimelineView(.animation) { context in
                        let travel = Double(over / speed)
                        let cycle = 2 * (travel + rest)
                        let t = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
                        // still, out, still, back
                        let phase = t < rest ? 0 : t < rest + travel ? (t - rest) / travel : t < 2 * rest + travel ? 1 : 1 - (t - 2 * rest - travel) / travel
                        let eased = phase * phase * (3 - 2 * phase)
                        line.font(font).fixedSize().offset(x: -over * eased)
                    }
                    .frame(width: room, alignment: .leading)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                               .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                }
            }
            .background {
                Text(text).font(font).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { full = $0 }
            }
            .onChange(of: text) { start = Date() }
    }
}

/// A section's title that folds it: tap to hide or show what's under it, a chevron saying which, and
/// something short beside it (a count, a value) that stays in sight while folded.
private struct Fold<Extra: View>: View {
    let title: String
    @Binding var open: Bool
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        Button {
            withAnimation(.snappy) { open.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Spacer()
                extra().foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(open ? 0 : -90))
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: open)
        .accessibilityLabel(title)
        .accessibilityValue(open ? "Shown" : "Hidden")
        .accessibilityHint("Double-tap to \(open ? "hide" : "show") it")
    }
}
