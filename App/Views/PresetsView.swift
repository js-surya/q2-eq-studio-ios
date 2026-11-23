// SPDX-License-Identifier: GPL-3.0-only
// AutoEq's presets for thousands of headphones and IEMs, from the card: a short list before a search,
// at most 200 rows after one, as EQ Studio's page shows them. A pick plays at once; Undo takes it back.
import EQCore
import SwiftUI

struct PresetsView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.horizontalSizeClass) private var width
    @State private var search = ""
    @FocusState private var searchFocus: Bool
    @State private var scope = Kind.all
    @State private var picked: String?

    enum Kind: String, CaseIterable {
        case all = "All", inEar = "In-Ear", overEar = "Over-Ear", earbud = "Earbuds"
        var type: String? {
            switch self {
            case .all: nil
            case .inEar: "in-ear"
            case .overEar: "over-ear"
            case .earbud: "earbud"
            }
        }
    }

    var body: some View {
        List {
            if width == .regular {
                Section {
                    GraphView(interactive: false, inRow: true)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
            }
            if let c = studio.catalogue {
                let rows = rows(c)
                Section {
                    ForEach(rows) { entry in
                        Button { pick(entry) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name).foregroundStyle(.primary)
                                    Text("\(entry.source) · \(entry.type.replacingOccurrences(of: "-", with: " ").capitalized)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if picked == entry.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(search.isEmpty ? "Popular" : "\(rows.count == 200 ? "First 200" : "\(rows.count)") Results")
                } footer: {
                    Text(c.credit)
                }
                if !search.isEmpty && rows.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            } else if let e = studio.catalogueError {
                ContentUnavailableView {
                    Label("No Presets", systemImage: "headphones")
                } description: {
                    Text(e)
                } actions: {
                    Button("Try Again") { Task { await studio.loadCatalogue() } }
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView("Loading AutoEq's presets…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Presets")
        .searchFocused($searchFocus)
        .onChange(of: studio.searchAsked) { searchFocus = true }
        .searchable(text: $search, prompt: "Headphones and IEMs")
        .searchScopes($scope) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) } }
        .task { if studio.catalogue == nil || studio.catalogueError != nil { await studio.loadCatalogue() } }
        .refreshable { await studio.loadCatalogue() }
    }

    private func rows(_ c: Catalogue) -> [Catalogue.Entry] {
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            return c.top.filter { scope.type == nil || $0.type == scope.type }
        }
        return c.search(search, type: scope.type, limit: 200)
    }

    private func pick(_ entry: Catalogue.Entry) {
        studio.apply(entry)
        picked = entry.id
    }
}
