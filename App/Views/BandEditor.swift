// SPDX-License-Identifier: GPL-3.0-only
// The picked band, in an inspector: beside the EQ on an iPad or an unfolded iPhone Duo, a sheet on
// an iPhone. Frequency and Q on log sliders, each value typed in place too.
import EQCore
import SwiftUI

struct BandEditor: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        NavigationStack {
            if let i = studio.band(studio.selected) {
                let band = studio.preset.bands[i]
                let knob = Knob.of(band)
                Form {
                    Section {
                        Toggle("On", isOn: bind(i, \.on, "on"))
                        Picker("Type", selection: bind(i, \.type, "type")) {
                            ForEach(FilterType.allCases, id: \.self) { Text(Format.typeName($0)) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(knob != nil)
                        Picker("Channel", selection: bind(i, \.channel, "channel")) {
                            ForEach(Channel.allCases, id: \.self) { Text(Format.channelName($0)) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(knob != nil)
                    } footer: {
                        if let knob { Text("\(knob.title) is Poweramp's knob: only its gain moves.") }
                    }

                    Section("Frequency") {
                        LogField(value: band.freq, range: EQ.freqMin...EQ.freqMax, digits: 0, unit: "Hz", format: Format.hertz) { v in
                            set(i, "freq") { $0.freq = (v * 100).rounded() / 100 }
                        }
                        .disabled(knob != nil)
                    }
                    Section("Gain") {
                        NumberField(value: band.gain, range: (knob != nil ? 0 : -EQ.gainMax)...(knob != nil ? Knob.maxGain : EQ.gainMax),
                                    step: 0.1, unit: "dB", format: { Format.dB($0) }) { v in
                            set(i, "gain") { $0.gain = (v * 100).rounded() / 100 }
                        }
                    }
                    Section("Q") {
                        LogField(value: band.q, range: EQ.qMin...EQ.qMax, digits: 2, unit: "", format: Format.q) { v in
                            set(i, "q") { $0.q = (v * 1000).rounded() / 1000 }
                        }
                        .disabled(knob != nil)
                    }
                    Section {
                        Button("Delete Band", systemImage: "trash", role: .destructive) { studio.deleteBand(band.id) }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Band \(i + 1)")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Previous", systemImage: "chevron.up") { pick(i - 1) }
                            .disabled(i == 0)
                            .keyboardShortcut("[", modifiers: [])
                        Button("Next", systemImage: "chevron.down") { pick(i + 1) }
                            .disabled(i + 1 >= studio.preset.bands.count)
                            .keyboardShortcut("]", modifiers: [])
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", systemImage: "checkmark") { studio.selected = nil }
                    }
                }
            } else {
                ContentUnavailableView("No Band", systemImage: "slider.horizontal.3", description: Text("Pick a band to edit it."))
            }
        }
    }

    private func pick(_ i: Int) {
        guard studio.preset.bands.indices.contains(i) else { return }
        studio.selected = studio.preset.bands[i].id
    }

    private func set(_ i: Int, _ field: String, _ edit: @escaping (inout Band) -> Void) {
        let id = studio.preset.bands[i].id
        studio.change("\(field)-\(id)") { p in
            if let k = p.bands.firstIndex(where: { $0.id == id }) { edit(&p.bands[k]) }
        }
    }

    private func bind<T>(_ i: Int, _ key: WritableKeyPath<Band, T>, _ field: String) -> Binding<T> {
        Binding(get: { studio.preset.bands[min(i, studio.preset.bands.count - 1)][keyPath: key] },
                set: { v in set(i, field) { $0[keyPath: key] = v } })
    }
}

/// A value on a log slider, with the number typed beside it.
private struct LogField: View {
    let value: Double
    let range: ClosedRange<Double>
    let digits: Int
    let unit: String
    let format: (Double) -> String
    let set: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(format(value)).font(.title3.weight(.semibold).monospacedDigit())
                Spacer()
                TypedNumber(value: value, range: range, digits: digits, unit: unit, set: set)
            }
            Slider(value: Binding(get: { log10(value) }, set: { set(pow(10, $0)) }),
                   in: log10(range.lowerBound)...log10(range.upperBound))
        }
    }
}

private struct NumberField: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let format: (Double) -> String
    let set: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(format(value)).font(.title3.weight(.semibold).monospacedDigit())
                Spacer()
                Stepper("", value: Binding(get: { value }, set: { set(min(max($0, range.lowerBound), range.upperBound)) }),
                        in: range, step: step)
                    .labelsHidden()
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                                  set: { set(($0 / step).rounded() * step) }), in: range)
        }
    }
}

/// Typed in place: 1.2k is 1200, as EQ Studio's table reads it.
private struct TypedNumber: View {
    let value: Double
    let range: ClosedRange<Double>
    let digits: Int
    let unit: String
    let set: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 80)
                .focused($focused)
                .keyboardType(.decimalPad)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
        }
        .onAppear { text = shown }
        .onChange(of: value) { if !focused { text = shown } }
    }

    private var shown: String { decimal(value, digits) }

    private func commit() {
        var t = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: ".")
        var scale = 1.0
        if t.hasSuffix("k") { scale = 1000; t.removeLast() }
        guard let v = Double(t) else { text = shown; return }
        set(min(max(v * scale, range.lowerBound), range.upperBound))
    }
}
