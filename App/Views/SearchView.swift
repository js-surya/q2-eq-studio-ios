// SPDX-License-Identifier: GPL-3.0-only
// The Search tab: AutoEq's presets and the picked reviewer's measurements, found together as you type.
// A preset plays when picked; a measurement goes under the EQ, as on Response.
import EQCore
import SwiftUI

struct SearchView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.horizontalSizeClass) private var width
    @State private var query = ""
    @State private var picked: String?
    var goToEQ: () -> Void = {}

    private static let rows = 25

    var body: some View {
        let words = query.trimmingCharacters(in: .whitespaces)
        let presets = words.isEmpty ? [] : studio.catalogue?.search(words, limit: Self.rows) ?? []
        let r = studio.response
        let measured = words.isEmpty ? [] : Array(r.found(words).prefix(Self.rows))
        List {
            if words.isEmpty {
                ContentUnavailableView {
                    Label("Search Headphones and IEMs", systemImage: "magnifyingglass")
                } description: {
                    Text("AutoEq's presets to play, and \(r.currentSite?.name ?? "squig.link")'s measurements to see under your EQ.")
                }
                .listRowBackground(Color.clear)
            } else {
                if !presets.isEmpty {
                    Section("Presets") {
                        ForEach(presets) { entry in
                            Button {
                                studio.apply(entry)
                                picked = entry.id
                            } label: {
                                Row(title: entry.name, detail: "\(entry.source) · \(entry.type.replacingOccurrences(of: "-", with: " ").capitalized)",
                                    icon: "headphones", on: picked == entry.id)
                            }
                            .buttonStyle(.plain)
                        }
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
                if presets.isEmpty && measured.isEmpty {
                    ContentUnavailableView.search(text: words).listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Headphones and IEMs")
        #if DEBUG
        .onAppear { if let q = ProcessInfo.processInfo.environment["EQS_QUERY"] { query = q } } // for screenshots
        #endif
        .task {
            if studio.catalogue == nil { await studio.loadCatalogue() }
            if r.sites == nil { await r.load() }
        }
    }

    private func show(_ phone: Squig.Phone, _ site: Squig.Site) {
        let r = studio.response
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
