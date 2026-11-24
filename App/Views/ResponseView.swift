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
    /// The reviewer the search moved away from, having no match, for the note under the pickers.
    @State private var movedFrom: String?
    @FocusState private var searchFocus: Bool
    var goToEQ: () -> Void = {}

    private static let rows = 200

    var body: some View {
        let r = studio.response
        let site = r.currentSite
        let phones = site.flatMap { r.books[$0.id] }
        let found = r.found(search)
        let query = search.trimmingCharacters(in: .whitespaces)
        // While searching, once every list is read: only the reviewers with a match, and how many.
        let counts = query.isEmpty ? [:] : r.reviewers(matching: query)
        let narrowing = !query.isEmpty && r.everyLoaded
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
                Picker("Measured by", selection: Binding(get: { site?.id ?? r.site }, set: { r.site = $0; movedFrom = nil })) {
                    if let sites = r.sites {
                        ForEach(Squig.kinds, id: \.kind) { kind in
                            let group = sites.filter { $0.kind == kind.kind && (!narrowing || counts[$0.id] != nil || $0.id == site?.id) }
                            if !group.isEmpty {
                                Section(kind.title) {
                                    ForEach(group) { s in
                                        Text(narrowing ? "\(s.name) · \(counts[s.id] ?? 0)" : s.name).tag(s.id)
                                    }
                                }
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
                Text(note(r, site, phones, found, counts: narrowing ? counts : nil))
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
        .onChange(of: studio.searchAsked) { takeSearch() }
        .onChange(of: studio.responseSearchAsked) { openSearch() }
        .onAppear { takeSearch(); openSearch() }
        // On an iPhone the field stays under the title, not hidden until the list is pulled down; an iPad's
        // is in the bar, in sight already.
        .searchable(text: $search, placement: width == .compact ? .navigationBarDrawer(displayMode: .always) : .automatic,
                    prompt: phones.map { "Search \($0.count.formatted()) \(r.kindWord)" } ?? "Search")
        .searchFocused($searchFocus) // after .searchable, so it reaches the field
        .task { await r.load() }
        // A pull reads squig.link again: the reviewers, this one's list, and while searching, everyone's.
        .refreshable {
            await r.refresh()
            if !search.trimmingCharacters(in: .whitespaces).isEmpty { await r.loadEvery() }
        }
        // A search reads every reviewer's list (once a day), to narrow "Measured by" to those with a match.
        .task(id: query.isEmpty) { if !query.isEmpty { await r.loadEvery() } }
        .onChange(of: counts) { follow(counts) }
        .onChange(of: query.isEmpty) { if query.isEmpty { movedFrom = nil } }
    }

    private func note(_ r: Response, _ site: Squig.Site?, _ phones: [Squig.Phone]?, _ found: [Squig.Phone],
                      counts: [String: Int]?) -> String {
        if !r.fetching.isEmpty { return "Loading \(r.fetching)…" }
        if let e = r.error?.errorDescription { return e }
        guard let site, let phones else {
            return site.map { "Loading \($0.name)'s list from squig.link…" } ?? "Loading the reviewers from squig.link…"
        }
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            var lead = ""
            if r.everyLoading {
                lead = "Searching every reviewer… "
            } else if let counts {
                let n = counts.count
                lead = n == 0 ? "No reviewer has measured a match. Try fewer words. "
                    : "\(n) \(n == 1 ? "reviewer has" : "reviewers have") measured a match; Measured by lists just \(n == 1 ? "that one" : "those"). "
                if let movedFrom { lead += "\(movedFrom) hasn't measured it, so this is \(site.name)'s. " }
            }
            if found.isEmpty { return lead + (counts == nil ? "No match. Try fewer words, or another reviewer." : "") }
            if found.count > Self.rows { return lead + "The first \(Self.rows) of \(found.count.formatted()) matches. Add a word to narrow it." }
            return lead + "\(found.count.formatted()) \(found.count == 1 ? "match" : "matches") here."
        }
        return "\(site.name) measured \(phones.count.formatted()) \(r.kindWord)\(phones.count > Self.rows ? ", the first \(Self.rows) shown; search for the rest" : ""). "
            + "Pick one to see it under your EQ. The measurement and the target are only drawn: the Q2 plays the EQ, and neither is saved or sent to it."
    }

    /// The picked reviewer has no match but others do: the one of the same kind (in-ears, headphones…)
    /// with the most, else the one with the most.
    private func follow(_ counts: [String: Int]) {
        let r = studio.response
        guard !counts.isEmpty, let sites = r.sites, let now = r.currentSite, counts[now.id] == nil else { return }
        let best = sites.filter { counts[$0.id] != nil }.max { a, b in
            let (x, y) = (a.kind == now.kind, b.kind == now.kind)
            return x != y ? !x : counts[a.id]! < counts[b.id]!
        }
        guard let best else { return }
        movedFrom = movedFrom ?? now.name
        r.site = best.id
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

    /// The tab opened: the cursor in the search, the keyboard up, as on Presets.
    private func openSearch() {
        guard studio.responseSearchAsked != nil else { return }
        studio.responseSearchAsked = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150)) // the search field is in place a moment after the tab
            searchFocus = true
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
    @State private var roomy = true // the row has room for AutoEQ's word beside the name

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
                    // Labelled where the row is wide enough, the icon alone where it isn't; at its own size
                    // (a ViewThatFits here, in a list's row, drew an empty pill the row's height).
                    fit(labelled: roomy).fixedSize()
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size.width >= 380 } action: { roomy = $0 }
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
                HStack(spacing: 5) { Image(systemName: "wand.and.stars"); Text("AutoEQ") }
            } else {
                Image(systemName: "wand.and.stars").accessibilityLabel("AutoEQ")
            }
        }
        // Filled, not glass: in a list's row on iOS 27.1 the glass one drew as an empty pill the row's height
        .buttonStyle(.borderedProminent)
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
