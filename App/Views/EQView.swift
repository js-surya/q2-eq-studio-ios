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
        List(selection: $studio.selected) {
            Section {
                GraphView()
                    .frame(height: width == .regular ? 320 : 250)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .selectionDisabled()
            } footer: {
                Text("Drag a dot to move its band. Pinch to change the picked band's width. Double-tap to add a band.")
            }

            Section {
                ForEach(Array(studio.preset.bands.enumerated()), id: \.element.id) { index, band in
                    BandRow(index: index, band: band)
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
                LabeledContent("At 48 kHz", value: Format.dB(autoPreamp(p)))
                    .foregroundStyle(.secondary)
            } else {
                ValueSlider(title: "Preamp", value: p.preamp, range: -24...12, step: 0.1, format: { Format.dB($0) }) { v in
                    studio.change("preamp") { $0.preamp = v }
                }
            }
            ValueSlider(title: "Balance", value: p.balance, range: -EQ.balanceMax...EQ.balanceMax, step: 0.1,
                        format: balanceText) { v in studio.change("balance") { $0.balance = v } }
        } header: {
            Text("Preamp and Balance")
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
                Button("Copy as Text", systemImage: "doc.on.doc") { Clipboard.copy(studio.text) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste Preset", systemImage: "doc.on.clipboard") {
                    if let t = Clipboard.text() { studio.open(text: t, name: studio.preset.name).map { pasteError = $0 } }
                }
                Divider()
                Button("Reset to Flat", systemImage: "arrow.counterclockwise", role: .destructive) {
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
