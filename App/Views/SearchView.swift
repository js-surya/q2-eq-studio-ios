// SPDX-License-Identifier: GPL-3.0-only
// The Search tab: AutoEq's presets and the picked reviewer's measurements, found together as you type.
// A preset plays when picked; a measurement goes under the EQ, as on Response.
import EQCore
import SwiftUI

struct SearchView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.horizontalSizeClass) private var width
    @State private var query = ""
    @State private var kind: String?
    @State private var picked: String?
    @State private var recents: [Recent] = Recent.load()
    @FocusState private var searchFocus: Bool
    @State private var shownEntry: Catalogue.Entry? // debug: EQS_PRESET opens a preset's page
    var goToEQ: () -> Void = {}

    private static let rows = 25

    var body: some View {
        let words = query.trimmingCharacters(in: .whitespaces)
        let browsing = words.isEmpty && kind != nil
        let presets = words.isEmpty ? (browsing ? Array((studio.catalogue?.search("", type: kind, limit: Self.rows * 2) ?? []).prefix(Self.rows * 2)) : [])
            : studio.catalogue?.search(words, type: kind, limit: Self.rows) ?? []
        let r = studio.response
        let measured = words.isEmpty ? [] : Array(r.found(words).prefix(Self.rows))
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("In-Ear", "in-ear", "earbuds"), ("Over-Ear", "over-ear", "headphones"), ("Earbuds", "earbud", "earbuds.case")], id: \.1) { title, type, icon in
                            let on = kind == type
                            Button { withAnimation(.snappy) { kind = on ? nil : type } } label: {
                                Label(title, systemImage: icon)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .foregroundStyle(on ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(on ? .regular.tint(studio.accent).interactive() : .regular.interactive(), in: .capsule)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            } footer: {
                if words.isEmpty && kind == nil {
                    Text("Find AutoEq's presets to play, and \(r.currentSite?.name ?? "squig.link")'s measurements to see under your EQ.")
                }
            }
            if words.isEmpty && kind == nil {
                if !recents.isEmpty {
                    Section {
                        ForEach(recents) { item in
                            if let key = item.preset, let entry = studio.catalogue?.presets.first(where: { $0.id == key }) {
                                NavigationLink(value: entry) {
                                    Row(title: item.name, detail: item.detail, icon: "clock.arrow.circlepath", on: studio.playing == key)
                                }
                            } else {
                                Button { replay(item) } label: {
                                    Row(title: item.name, detail: item.detail, icon: "waveform.path.ecg", on: false,
                                        busy: r.fetching == item.name)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Recent")
                            Spacer()
                            Button("Clear") { withAnimation { recents = []; Recent.save([]) } }.font(.footnote)
                        }
                    }
                }
                if let top = studio.catalogue?.top, !top.isEmpty {
                    Section("Popular Presets") {
                        ForEach(top.prefix(8)) { entry in presetRow(entry) }
                    }
                } else if studio.catalogueLoading {
                    HStack { Spacer(); ProgressView("Loading AutoEq's presets…"); Spacer() }.listRowBackground(Color.clear)
                }
            } else {
                if !presets.isEmpty {
                    Section(browsing ? "Presets" : "Presets") {
                        ForEach(presets) { entry in presetRow(entry) }
                    }
                }
                if !measured.isEmpty, let site = r.currentSite {
                    Section("Measured by \(site.name)") {
                        ForEach(measured) { phone in
                            Button { show(phone, site) } label: {
                                Row(title: phone.name, detail: "Show it under your EQ", icon: "waveform.path.ecg",
                                    on: r.shown?.file == phone.file && r.shown?.base == site.base, busy: r.fetching == phone.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if presets.isEmpty && measured.isEmpty && !words.isEmpty {
                    ContentUnavailableView.search(text: words).listRowBackground(Color.clear)
                }
            }
        }
        .pinnedGraph(width == .regular) { GraphView(interactive: false, inRow: true).frame(height: 200) }
        .navigationTitle("Presets")
        .settingsButton()
        #if DEBUG
        .navigationDestination(item: $shownEntry) { entry in PresetPage(entry: entry) {} }
        .onChange(of: studio.catalogue?.presets.count) {
            if let q = ProcessInfo.processInfo.environment["EQS_PRESET"], shownEntry == nil {
                shownEntry = studio.catalogue?.search(q, limit: 1).first
            }
        }
        #endif
        .navigationDestination(for: Catalogue.Entry.self) { entry in
            PresetPage(entry: entry) {
                remember(Recent(name: entry.name, detail: "\(entry.source) · \(entry.type.replacingOccurrences(of: "-", with: " ").capitalized)",
                                preset: entry.id))
            }
        }
        .searchable(text: $query, prompt: "Headphones and IEMs")
        .searchFocused($searchFocus)
        .onChange(of: studio.searchAsked) { takeSearch() }
        .onAppear { takeSearch() }
        .refreshable { await studio.loadCatalogue() }
        #if DEBUG
        .onAppear { if let q = ProcessInfo.processInfo.environment["EQS_QUERY"] { query = q } } // for screenshots
        #endif
        .task {
            if studio.catalogue == nil { await studio.loadCatalogue() }
            if r.sites == nil { await r.load() }
        }
    }

    /// / asked for the search: focused once this tab is on screen.
    private func takeSearch() {
        guard studio.searchAsked != nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["EQS_NOFOCUS"] != nil { studio.searchAsked = nil; return } // screenshots
        #endif
        studio.searchAsked = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            searchFocus = true
        }
    }

    /// A preset's row: it opens the preset's page, to look at before applying.
    private func presetRow(_ entry: Catalogue.Entry) -> some View {
        NavigationLink(value: entry) {
            Row(title: entry.name, detail: "\(entry.source) · \(entry.type.replacingOccurrences(of: "-", with: " ").capitalized)",
                icon: "headphones", on: studio.playing == entry.id)
        }
    }

    private func remember(_ item: Recent) {
        recents.removeAll { $0.id == item.id }
        recents.insert(item, at: 0)
        recents = Array(recents.prefix(8))
        Recent.save(recents)
    }

    private func replay(_ item: Recent) {
        if let key = item.preset, let entry = studio.catalogue?.presets.first(where: { $0.id == key }) {
            studio.apply(entry)
            remember(item)
        } else if let base = item.base, let file = item.file, let by = item.by {
            show(Squig.Phone(name: item.name, file: file, find: item.name.lowercased()),
                 Squig.Site(id: base, name: by, kind: item.kind ?? "IEMs", base: base))
        }
    }

    private func show(_ phone: Squig.Phone, _ site: Squig.Site) {
        let r = studio.response
        remember(Recent(name: phone.name, detail: "Measured by \(site.name)", base: site.base, file: phone.file, by: site.name, kind: site.kind))
        r.fetching = phone.name
        Task {
            defer { if r.fetching == phone.name { r.fetching = "" } }
            do {
                guard try await r.show(base: site.base, file: phone.file, name: phone.name, by: site.name, kind: site.kind) else { return }
                studio.buzz(.success)
                if width != .regular { goToEQ() }
                studio.say("\(phone.name) is on the graph, under your EQ.")
            } catch {
                studio.tell("\(phone.name) couldn't be loaded", error.localizedDescription)
            }
        }
    }
}

private struct Row: View {
    let title, detail, icon: String
    let on: Bool
    var busy = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) } else if on {
                Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
    }
}

/// A preset or a measurement picked here, kept for the Recent list.
struct Recent: Codable, Identifiable {
    var name: String
    var detail: String
    var preset: String? // a catalogue entry's id
    var base: String?, file: String?, by: String?, kind: String? // a measurement's
    var id: String { preset ?? "\(base ?? "")\u{1}\(file ?? "")" }
    var measurement: Bool { preset == nil }

    private static let key = "eq-studio-recent"
    static func load() -> [Recent] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Recent].self, from: $0) } ?? []
    }
    static func save(_ list: [Recent]) {
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: key) }
    }
}

/// A preset's page: its curve, read only, over the EQ playing now; its bands; and Apply, which plays it.
struct PresetPage: View {
    @Environment(Studio.self) private var studio
    @Environment(\.horizontalSizeClass) private var width
    let entry: Catalogue.Entry
    let applied: () -> Void

    /// The two lines' key, under the graph.
    private var legend: some View {
        HStack(spacing: 14) {
            Label("This preset", systemImage: "circle.fill").foregroundStyle(BandColor.accent)
            Label("Playing now", systemImage: "circle.dashed").foregroundStyle(.secondary)
        }
        .font(.caption)
        .imageScale(.small)
    }

    var body: some View {
        let preset = (try? parse(entry.text, name: entry.name).get()).map(normalize)
        let playing = studio.playing == entry.id
        List {
            if let preset {
                if width != .regular { // where there's room it's held over the list instead (pinnedGraph)
                    Section {
                        PreviewGraph(preset: preset, now: studio.preset)
                            .frame(height: 240)
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    } footer: {
                        legend
                    }
                }
                Section {
                    LabeledContent("Measured by", value: entry.source)
                    LabeledContent("Kind", value: entry.type.replacingOccurrences(of: "-", with: " ").capitalized)
                    LabeledContent("Preamp", value: preset.auto ? "Auto" : Format.dB(preset.preamp))
                }
                Section("\(preset.bands.count) Bands") {
                    ForEach(Array(preset.bands.enumerated()), id: \.offset) { i, band in
                        HStack(spacing: 12) {
                            Text("\(i + 1)")
                                .font(.footnote.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(BandColor.of(band), in: .circle)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Format.hertz(band.freq)).font(.body.weight(.semibold).monospacedDigit())
                                Text("\(Format.typeName(band.type)) · \(Format.q(band.q))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Format.dB(band.gain)).monospacedDigit()
                        }
                    }
                }
                Section {
                } footer: {
                    Text(entry.source == "" ? "" : "From the AutoEq project, computed from \(entry.source)'s measurement.")
                }
            } else {
                ContentUnavailableView("This preset can't be read", systemImage: "exclamationmark.triangle")
            }
        }
        .pinnedGraph(width == .regular && preset != nil) {
            if let preset {
                VStack(alignment: .leading, spacing: 6) {
                    PreviewGraph(preset: preset, now: studio.preset).frame(height: 240)
                    legend.padding(.horizontal, 12).padding(.bottom, 6)
                }
            }
        }
        .navigationTitle(entry.name)
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                studio.apply(entry)
                applied()
            } label: {
                Label(playing ? "Playing on the Q2" : "Apply", systemImage: playing ? "checkmark.circle.fill" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(playing || preset == nil)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

/// A preset's curve to look at: its curve and numbered dots, the EQ playing now dashed behind; nothing moves.
struct PreviewGraph: View {
    let preset: Preset
    let now: Preset

    var body: some View {
        let freqs = Plot.freqs
        let curve = responses(preset, at: freqs)
        let current = responses(now, at: freqs)
        var most = 0.0
        for p in curve { most = max(most, abs(p.left), abs(p.right)) }
        for p in current { most = max(most, abs(p.left)) }
        let range = min(max(ceil((most + 1) / 6) * 6, 12), 30)
        return Canvas { ctx, size in
            let rect = CGRect(x: 34, y: 10, width: max(size.width - 44, 1), height: max(size.height - 32, 1))
            let lo = log10(EQ.freqMin), span = log10(EQ.freqMax) - lo
            let x = { (f: Double) in rect.minX + rect.width * CGFloat((log10(f) - lo) / span) }
            let y = { (db: Double) in rect.midY - rect.height / 2 * CGFloat(min(max(db, -range), range) / range) }
            let grid = Color.secondary.opacity(0.18)
            for f in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] {
                var p = Path(); p.move(to: CGPoint(x: x(f), y: rect.minY)); p.addLine(to: CGPoint(x: x(f), y: rect.maxY))
                ctx.stroke(p, with: .color(grid), lineWidth: 0.5)
                ctx.draw(Text(Format.gridHertz(f)).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary), at: CGPoint(x: x(f), y: rect.maxY + 11))
            }
            var db = -range
            while db <= range + 0.01 {
                var p = Path(); p.move(to: CGPoint(x: rect.minX, y: y(db))); p.addLine(to: CGPoint(x: rect.maxX, y: y(db)))
                ctx.stroke(p, with: .color(db == 0 ? Color.secondary.opacity(0.5) : grid), lineWidth: db == 0 ? 1 : 0.5)
                ctx.draw(Text(db == 0 ? "0" : db > 0 ? "+\(Int(db))" : "−\(Int(-db))").font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.secondary),
                         at: CGPoint(x: rect.minX - 6, y: y(db)), anchor: .trailing)
                db += 6
            }
            let line = { (values: [Double]) -> Path in
                var p = Path()
                for (k, f) in freqs.enumerated() { k == 0 ? p.move(to: CGPoint(x: x(f), y: y(values[k]))) : p.addLine(to: CGPoint(x: x(f), y: y(values[k]))) }
                return p
            }
            ctx.stroke(line(current.map(\.left)), with: .color(.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            let mine = line(curve.map(\.left))
            var fill = mine
            fill.addLine(to: CGPoint(x: x(EQ.freqMax), y: y(0))); fill.addLine(to: CGPoint(x: x(EQ.freqMin), y: y(0))); fill.closeSubpath()
            ctx.fill(fill, with: .color(BandColor.accent.opacity(0.14)))
            ctx.stroke(mine, with: .color(BandColor.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for (i, b) in preset.bands.enumerated() {
                let c = CGPoint(x: x(b.freq), y: y(b.gain))
                let r = CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)
                ctx.fill(Path(ellipseIn: r), with: .color(Color.rowBackground))
                ctx.stroke(Path(ellipseIn: r), with: .color(BandColor.of(b)), style: StrokeStyle(lineWidth: 2, dash: b.on ? [] : [3, 3]))
                ctx.draw(Text("\(i + 1)").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(BandColor.of(b)), at: c)
            }
        }
        .accessibilityLabel("The preset's curve")
    }
}
