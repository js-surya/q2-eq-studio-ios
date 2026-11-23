// SPDX-License-Identifier: GPL-3.0-only
// The Response tab, as EQ Studio's page has it: pick who measured (any reviewer on squig.link, Super*
// Review first), search, and pick an earphone or headphone; it's drawn under the EQ, with the EQ added to
// it. A target beside it, and AutoEQ to fit the bands to it.
import EQCore
import SwiftUI

struct ResponseView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.horizontalSizeClass) private var width
    @State private var search = ""
    @FocusState private var searchFocus: Bool
    var goToEQ: () -> Void = {}

    private static let rows = 200

    var body: some View {
        let r = studio.response
        let site = r.currentSite
        let phones = site.flatMap { r.books[$0.id] }
        let found = r.found(search)
        List {
            if width == .regular {
                Section {
                    GraphView(interactive: false, inRow: true)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    ShownBar()
                }
            }
            Section {
                Picker("Measured by", selection: Binding(get: { site?.id ?? r.site }, set: { r.site = $0 })) {
                    if let sites = r.sites {
                        ForEach(Squig.kinds, id: \.kind) { kind in
                            let group = sites.filter { $0.kind == kind.kind }
                            if !group.isEmpty {
                                Section(kind.title) { ForEach(group) { Text($0.name).tag($0.id) } }
                            }
                        }
                    } else {
                        Text(r.error == nil ? "Loading…" : "Not loaded").tag(r.site)
                    }
                }
                .disabled(r.sites == nil)
                Picker("Target", selection: Binding(get: { r.target }, set: { r.target = $0 })) {
                    Text("None").tag("")
                    ForEach(Squig.targetKinds, id: \.kind) { kind in
                        Section(kind.title) {
                            ForEach(Squig.targets.filter { $0.kind == kind.kind }) { Text($0.name).tag($0.name) }
                        }
                    }
                }
            } footer: {
                Text(note(r, site, phones, found))
            }
            if r.error != nil && r.error?.status != 404 {
                Button("Try Again", systemImage: "arrow.clockwise") { Task { await r.load() } }
            }
            if phones != nil {
                Section {
                    ForEach(found.prefix(Self.rows)) { phone in
                        Button { pick(phone) } label: {
                            HStack {
                                Text(phone.name).foregroundStyle(.primary)
                                Spacer()
                                if r.fetching == phone.name {
                                    ProgressView().controlSize(.small)
                                } else if r.shown?.file == phone.file && r.shown?.base == site?.base {
                                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Response")
        .settingsButton()
        .searchFocused($searchFocus)
        .onChange(of: studio.searchAsked) { takeSearch() }
        .onAppear { takeSearch() }
        .searchable(text: $search, prompt: phones.map { "Search \($0.count.formatted()) \(r.kindWord)" } ?? "Search")
        .task { await r.load() }
        .refreshable { await r.load() }
    }

    private func note(_ r: Response, _ site: Squig.Site?, _ phones: [Squig.Phone]?, _ found: [Squig.Phone]) -> String {
        if !r.fetching.isEmpty { return "Loading \(r.fetching)…" }
        if let e = r.error?.errorDescription { return e }
        guard let site, let phones else {
            return site.map { "Loading \($0.name)'s list from squig.link…" } ?? "Loading the reviewers from squig.link…"
        }
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            if found.isEmpty { return "No match. Try fewer words, or another reviewer." }
            if found.count > Self.rows { return "The first \(Self.rows) of \(found.count.formatted()) matches. Add a word to narrow it." }
            return "\(found.count.formatted()) \(found.count == 1 ? "match" : "matches")."
        }
        return "\(site.name) measured \(phones.count.formatted()) \(r.kindWord)\(phones.count > Self.rows ? ", the first \(Self.rows) shown; search for the rest" : ""). "
            + "Pick one to see it under your EQ. The measurement and the target are only drawn: the Q2 plays the EQ, and neither is saved or sent to it."
    }

    /// The latest pick wins; a phone shows the graph on the EQ tab, so it goes there.
    private func pick(_ phone: Squig.Phone) {
        let r = studio.response
        guard let site = r.currentSite else { return }
        r.fetching = phone.name
        Task {
            defer { if r.fetching == phone.name { r.fetching = "" } }
            do {
                guard try await r.show(base: site.base, file: phone.file, name: phone.name, by: site.name, kind: site.kind) else { return }
                if width != .regular { goToEQ() }
                studio.buzz(.success)
                studio.say("\(phone.name) is on the graph, under your EQ.")
            } catch {
                studio.tell("\(phone.name) couldn't be loaded", error.localizedDescription)
            }
        }
    }

    /// / asked for the search: focused once this tab is on screen, even when / brought it here.
    private func takeSearch() {
        guard studio.searchAsked != nil else { return }
        studio.searchAsked = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150)) // the search field is in place a moment after the tab
            searchFocus = true
        }
    }
}

/// Under the graph while a measurement is on it: its name (tap to take it off) and AutoEQ.
struct ShownBar: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        let r = studio.response
        if let shown = r.shown {
            HStack(spacing: 10) {
                Button {
                    let name = shown.name
                    r.clear()
                    studio.say("\(name) is off the graph.")
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shown.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(r.target.isEmpty ? shown.by : "\(shown.by) → \(r.target)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("\(shown.name), measured by \(shown.by). Take it off the graph.")
                .accessibilityLabel("Take \(shown.name) off the graph")
                .layoutPriority(1)
                Spacer(minLength: 4)
                if !r.target.isEmpty {
                    // Labelled while the name fits beside it; the icon alone when it doesn't.
                    ViewThatFits(in: .horizontal) {
                        fit(labelled: true).fixedSize()
                        fit(labelled: false)
                    }
                    .frame(minWidth: 44, alignment: .trailing)
                }
            }
        }
    }

    private func fit(labelled: Bool) -> some View {
        let r = studio.response
        return Button {
            Task { await autoEQ() }
        } label: {
            if r.fitting {
                ProgressView().controlSize(.mini)
            } else if labelled {
                Label("AutoEQ", systemImage: "wand.and.stars")
            } else {
                Image(systemName: "wand.and.stars").accessibilityLabel("AutoEQ")
            }
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(labelled ? .capsule : .circle)
        .controlSize(.small)
        .font(.subheadline.weight(.semibold))
        .disabled(r.fitting)
        .help("Fit the bands to bring \(r.shown?.name ?? "it") to \(r.target)")
    }

    private func autoEQ() async {
        let r = studio.response
        guard let shown = r.shown else { return }
        studio.say("Fitting \(shown.name) to \(r.target)…")
        do {
            if let (preset, _) = try await r.autoEQ() { studio.load(preset, notes: nil, how: "by AutoEQ") }
        } catch {
            if error.localizedDescription.contains("already") { studio.say(error.localizedDescription) } else {
                studio.tell("AutoEQ couldn't fit it", error.localizedDescription)
            }
        }
    }
}
