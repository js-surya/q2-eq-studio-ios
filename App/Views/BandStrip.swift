// SPDX-License-Identifier: GPL-3.0-only
// The picked band under the graph, on an iPhone as on an iPad, either way up: its controls next to the curve
// they move, nothing covering the bands. An iPad's is wide (segmented type and side, the values side by side);
// an iPhone's compact (menus, the values one under another).
import EQCore
import SwiftUI

struct BandStrip: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        Group {
            if let i = studio.band(studio.selected) {
                Card(index: i, band: studio.preset.bands[i])
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: studio.selected == nil)
    }
}

private struct Card: View {
    @Environment(Studio.self) private var studio
    @Environment(\.horizontalSizeClass) private var width
    let index: Int
    let band: Band

    var body: some View {
        if width == .compact { compact } else { wide }
    }

    /// An iPhone's: the name and its actions, type and side as menus, then frequency, gain and Q each a row.
    /// A pull down on its top line closes it, as ✕ does.
    private var compact: some View {
        let knob = Knob.of(band)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                title(knob)
                Spacer(minLength: 4)
                close
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { if $0.translation.height > 40 { studio.selected = nil } })
            HStack(spacing: 8) {
                Picker("Type", selection: field(\.type, "type")) {
                    ForEach(FilterType.allCases, id: \.self) { Text(Format.typeName($0)) }
                }
                .disabled(knob != nil)
                Picker("Side", selection: field(\.channel, "channel")) {
                    ForEach(Channel.allCases, id: \.self) { Text(Format.channelName($0)) }
                }
                .disabled(knob != nil)
                Spacer(minLength: 8)
                // Delete away from ✕ and named, so a near miss on close never deletes the band
                Button("Delete", systemImage: "trash", role: .destructive) { studio.deleteBand(band.id) }
                    .buttonStyle(.borderless) // red words, no fill: as a list's destructive action
                    .font(.subheadline.weight(.medium))
            }
            .pickerStyle(.menu)
            .buttonStyle(.bordered)
            .controlSize(.small)
            VStack(spacing: 6) { rows(knob) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.rowBackground, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(BandColor.of(band).opacity(0.35), lineWidth: 1)
        }
        .opacity(band.on ? 1 : 0.75)
    }

    @ViewBuilder private func rows(_ knob: Knob?) -> some View {
        Param(title: "Frequency", value: band.freq, range: EQ.freqMin...EQ.freqMax, log: true, digits: 0, unit: "Hz", row: true) { v in
            set("freq") { $0.freq = (v * 100).rounded() / 100 }
        }
        .disabled(knob != nil)
        Param(title: "Gain", value: band.gain,
              range: (knob != nil ? 0 : -EQ.gainMax)...(knob != nil ? Knob.maxGain : EQ.gainMax),
              log: false, digits: 1, unit: "dB", step: 0.1, row: true) { v in
            set("gain") { $0.gain = (v * 100).rounded() / 100 }
        }
        Param(title: "Q", value: band.q, range: EQ.qMin...EQ.qMax, log: true, digits: 2, unit: "", row: true) { v in
            set("q") { $0.q = (v * 1000).rounded() / 1000 }
        }
        .disabled(knob != nil)
    }

    private var wide: some View {
        let knob = Knob.of(band)
        return VStack(alignment: .leading, spacing: 14) {
            // One line where it fits; the type and side under the name where it doesn't (Split View).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    title(knob)
                    Spacer(minLength: 8)
                    pickers(knob).fixedSize()
                    actions
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) { title(knob); Spacer(minLength: 8); actions }
                    HStack(spacing: 10) { pickers(knob) }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { values(knob).frame(minWidth: 210) }
                VStack(spacing: 14) { values(knob) }
            }
        }
        .padding(16)
        .background(Color.rowBackground, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(BandColor.of(band).opacity(0.35), lineWidth: 1)
        }
        .opacity(band.on ? 1 : 0.75)
    }

    // MARK: The parts

    private func title(_ knob: Knob?) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(BandColor.of(band), in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text("Band \(index + 1)").font(.headline)
                if let knob { Text("\(knob.title): only its gain moves").font(.caption).foregroundStyle(.secondary) }
            }
            .fixedSize()
            HStack(spacing: 2) {
                Button("Previous Band", systemImage: "chevron.left") { pick(index - 1) }
                    .disabled(index == 0)
                Button("Next Band", systemImage: "chevron.right") { pick(index + 1) }
                    .disabled(index + 1 >= studio.preset.bands.count)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.body.weight(.semibold))
            .help("Previous or next band")
            Toggle("On", isOn: field(\.on, "on"))
                .fixedSize()
                .padding(.leading, 4)
        }
    }

    @ViewBuilder private func pickers(_ knob: Knob?) -> some View {
        Picker("Type", selection: field(\.type, "type")) {
            ForEach(FilterType.allCases, id: \.self) { Text(Format.typeName($0)) }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 250)
        .disabled(knob != nil)
        Picker("Side", selection: field(\.channel, "channel")) {
            ForEach(Channel.allCases, id: \.self) { Text(Format.channelName($0)) }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 170)
        .disabled(knob != nil)
    }

    /// The compact card's close alone: its Delete is on the line under it.
    private var close: some View {
        Button("Done", systemImage: "xmark") { studio.selected = nil }
            .tint(.secondary)
            .help("Done")
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .fixedSize()
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button("Delete Band", systemImage: "trash", role: .destructive) { studio.deleteBand(band.id) }
                .tint(.red)
            Button("Done", systemImage: "xmark") { studio.selected = nil }
                .tint(.secondary)
                .help("Done")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .fixedSize()
    }

    @ViewBuilder private func values(_ knob: Knob?) -> some View {
        Param(title: "Frequency", value: band.freq, range: EQ.freqMin...EQ.freqMax, log: true, digits: 0, unit: "Hz") { v in
            set("freq") { $0.freq = (v * 100).rounded() / 100 }
        }
        .disabled(knob != nil)
        Param(title: "Gain", value: band.gain,
              range: (knob != nil ? 0 : -EQ.gainMax)...(knob != nil ? Knob.maxGain : EQ.gainMax),
              log: false, digits: 1, unit: "dB", step: 0.1) { v in
            set("gain") { $0.gain = (v * 100).rounded() / 100 }
        }
        Param(title: "Q", value: band.q, range: EQ.qMin...EQ.qMax, log: true, digits: 2, unit: "") { v in
            set("q") { $0.q = (v * 1000).rounded() / 1000 }
        }
        .disabled(knob != nil)
    }

    // MARK: Editing

    private func pick(_ i: Int) {
        guard studio.preset.bands.indices.contains(i) else { return }
        studio.selected = studio.preset.bands[i].id
    }

    private func set(_ name: String, _ edit: @escaping (inout Band) -> Void) {
        let id = band.id
        studio.change("\(name)-\(id)") { p in if let k = p.bands.firstIndex(where: { $0.id == id }) { edit(&p.bands[k]) } }
    }

    private func field<T>(_ key: WritableKeyPath<Band, T>, _ name: String) -> Binding<T> {
        Binding(get: { band[keyPath: key] }, set: { v in set(name) { $0[keyPath: key] = v } })
    }
}

/// A value: its name and the number typed in place above a slider (a log one for frequency and Q).
private struct Param: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let log: Bool
    let digits: Int
    let unit: String
    var step: Double = 0
    var row = false // an iPhone's: the name, the slider and the number on one line
    let set: (Double) -> Void

    var body: some View {
        Group {
            if row {
                HStack(spacing: 10) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    Slider(value: slider, in: log ? log10(range.lowerBound)...log10(range.upperBound) : range)
                    TypedNumber(value: value, range: range, digits: digits, unit: unit, width: 58, set: set)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        TypedNumber(value: value, range: range, digits: digits, unit: unit, set: set)
                    }
                    Slider(value: slider, in: log ? log10(range.lowerBound)...log10(range.upperBound) : range)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        // A tick each whole dB on gain, a bump at 0, as Bass and Treble have.
        .sensoryFeedback(trigger: log ? 0 : Int(value.rounded(.towardZero))) { old, new in
            new == 0 && old != 0 ? .impact(weight: .medium, intensity: 0.8) : .selection
        }
    }

    private var slider: Binding<Double> {
        if log {
            return Binding(get: { log10(min(max(value, range.lowerBound), range.upperBound)) }, set: { set(pow(10, $0)) })
        }
        return Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                       set: { set(step > 0 ? ($0 / step).rounded() * step : $0) })
    }
}

/// Typed in place: 1.2k is 1200, as EQ Studio's table reads it.
struct TypedNumber: View {
    let value: Double
    let range: ClosedRange<Double>
    let digits: Int
    let unit: String
    var width: CGFloat = 80
    let set: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
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
