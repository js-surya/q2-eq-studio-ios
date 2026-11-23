// SPDX-License-Identifier: GPL-3.0-only
// The card's EQ folder, where the Q2's EQ page imports presets from (Import from SD /EQ): open one,
// save this EQ there, delete one. Open a file, share this one, copy and paste it as text.
import EQCore
import SwiftUI
import UniformTypeIdentifiers

struct CardView: View {
    @Environment(Studio.self) private var studio
    @State private var saving = false
    @State private var name = ""
    @State private var taken: String?
    @State private var deleting: CardFile?
    @State private var message: String?
    @State private var importing = false

    var body: some View {
        List {
            Section {
                Button("Save to the Card…", systemImage: "square.and.arrow.down") {
                    name = studio.preset.name.isEmpty ? EQ.fallbackName : studio.preset.name
                    saving = true
                }
                .keyboardShortcut("s", modifiers: .command)
            } footer: {
                if studio.live.local {
                    Text("This Q2 Pod can't take the EQ live. Save it here, then on the Q2 open the EQ page's Import from SD /EQ.")
                }
            }

            Section("On the Card") {
                if let e = studio.cardError {
                    Label(e, systemImage: "sdcard").foregroundStyle(.secondary)
                } else if studio.cardFiles.isEmpty && !studio.cardLoading {
                    Text("No presets in the card's EQ folder yet.").foregroundStyle(.secondary)
                }
                ForEach(studio.cardFiles) { file in
                    Button {
                        Task { message = await studio.open(file) }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).foregroundStyle(.primary)
                                Text(file.date, format: .relative(presentation: .named))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = file }
                    }
                    .contextMenu {
                        Button("Open", systemImage: "arrow.up.forward.app") { Task { message = await studio.open(file) } }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = file }
                    }
                }
            }

            Section {
                Button("Open File…", systemImage: "folder") { importing = true }
                    .keyboardShortcut("o", modifiers: .command)
                ShareLink(item: PresetFile(name: fileName(studio.preset.name), text: studio.text),
                          preview: SharePreview(fileName(studio.preset.name))) {
                    Label("Share This EQ", systemImage: "square.and.arrow.up")
                }
                Button("Copy as Text", systemImage: "doc.on.doc") { Clipboard.copy(studio.text) }
                Button("Paste a Preset", systemImage: "doc.on.clipboard") {
                    if let t = Clipboard.text() { message = studio.open(text: t, name: studio.preset.name) }
                }
            } header: {
                Text("Files and Other Apps")
            } footer: {
                Text("The text is Equalizer APO's format, as AutoEq and PEQdB Studio read and write it.")
            }
        }
        .navigationTitle("Card")
        .task { await studio.loadCard() }
        .refreshable { await studio.loadCard() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count <= EQ.fileMax else {
                message = "A preset is at most 16 KB."
                return
            }
            message = studio.open(text: String(decoding: data, as: UTF8.self), name: nameOfFile(url.lastPathComponent))
        }
        .alert("Save to the Card", isPresented: $saving) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { save(replace: false) }
        } message: {
            Text("It goes in the card's EQ folder as \(fileName(name)).")
        }
        .confirmationDialog("“\(taken ?? "")” is already on the card.", isPresented: Binding(get: { taken != nil }, set: { if !$0 { taken = nil } }),
                            titleVisibility: .visible) {
            Button("Replace", role: .destructive) { save(replace: true) }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")” from the card?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let f = deleting { Task { message = await studio.delete(f) } }
            }
        }
        .alert("EQ Studio", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: {
            Text(message ?? "")
        }
    }

    private func save(replace: Bool) {
        Task {
            switch await studio.save(as: name, replace: replace) {
            case .saved: message = "Saved to the card's EQ folder."
            case .taken: taken = fileName(name)
            case .failed(let why): message = why
            }
        }
    }
}

/// This EQ as a .txt file to share.
struct PresetFile: Transferable {
    let name: String
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let url = URL.temporaryDirectory.appending(path: file.name)
            try Data(file.text.utf8).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

enum Clipboard {
    static func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }

    static func text() -> String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}
