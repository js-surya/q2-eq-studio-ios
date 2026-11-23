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
            if width == .regular {
                Section {
                    GraphView(interactive: false, inRow: true)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
            }
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
                            .glassEffect(on ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
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
                            Button { replay(item) } label: {
                                Row(title: item.name, detail: item.detail, icon: item.measurement ? "waveform.path.ecg" : "clock.arrow.circlepath", on: false,
                                    busy: item.measurement && r.fetching == item.name)
                            }
                            .buttonStyle(.plain)
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
        .navigationTitle("Search")
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
        studio.searchAsked = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            searchFocus = true
        }
    }

    private func presetRow(_ entry: Catalogue.Entry) -> some View {
        Button {
            studio.apply(entry)
            picked = entry.id
            remember(Recent(name: entry.name, detail: "\(entry.source) · \(entry.type.replacingOccurrences(of: "-", with: " ").capitalized)",
                            preset: entry.id))
        } label: {
            Row(title: entry.name, detail: "\(entry.source) · \(entry.type.replacingOccurrences(of: "-", with: " ").capitalized)",
                icon: "headphones", on: picked == entry.id)
        }
        .buttonStyle(.plain)
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
