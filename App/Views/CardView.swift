// SPDX-License-Identifier: GPL-3.0-only
// The card's EQ folder, where the Q2's EQ page imports presets from (Import from SD /EQ): open one,
// save this EQ there, delete one. Open a file, share this one, copy and paste it as text.
import EQCore
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct CardView: View {
    @Environment(Studio.self) private var studio
    @State private var saving = false
    @State private var name = ""
    @State private var taken: String?
    @State private var deleting: CardFile?
    @State private var message: String?
    @State private var importing = false
    @State private var pasting = false
    @State private var exportFile: ExportFile?
    @State private var find = "" // the card's presets: words to find one by
    @State private var all = false // every preset, not just the latest saved
    private static let latest = 5

    var body: some View {
        List {
            Section {
                Button("Save to the Card…", systemImage: "square.and.arrow.down") { askSave() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(studio.link == nil)
                // The same preset file, kept on this device or in iCloud Drive, with or without a Q2.
                Button("Save to Files…", systemImage: "folder.badge.plus") { saveToFiles() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            } footer: {
                if studio.live.local {
                    Text("This Q2 Pod can't take the EQ live. Save it here, then on the Q2 open the EQ page's Import from SD /EQ.")
                } else {
                    Text("Save to Files keeps the preset on this \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") or in iCloud Drive; Open File brings it back.")
                }
            }

            Section {
                if studio.link == nil {
                    Label("Connect a Q2 to see the presets on its card.", systemImage: "sdcard").foregroundStyle(.secondary)
                    Button("Connect a Q2", systemImage: "qrcode.viewfinder") { studio.trying = false }
                } else if let e = studio.cardError {
                    Label(e, systemImage: "sdcard").foregroundStyle(.secondary)
                } else if studio.cardFiles.isEmpty && !studio.cardLoading {
                    Text("No presets in the card's EQ folder yet.").foregroundStyle(.secondary)
                }
                let files = studio.cardFiles
                let words = Response.words(find)
                // The latest saved first, five of them; a search looks through them all, dashes, spaces and
                // capitals aside, as Response's does; Show All lists every one by name.
                let found = words.isEmpty ? (all ? files : Array(files.sorted { $0.mtime > $1.mtime }.prefix(Self.latest)))
                    : files.filter { f in let key = Response.squash(f.name); return words.allSatisfy { key.contains($0) } }
                if files.count > Self.latest {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a preset on the card", text: $find)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                        if !find.isEmpty {
                            Button("Clear", systemImage: "xmark.circle.fill") { find = "" }
                                .labelStyle(.iconOnly).foregroundStyle(.secondary).buttonStyle(.borderless)
                        }
                    }
                }
                if !words.isEmpty && found.isEmpty {
                    Text("No preset on the card matches.").foregroundStyle(.secondary)
                }
                ForEach(found) { file in
                    Button {
                        Task { _ = await studio.open(file) }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).foregroundStyle(.primary)
                                Text(file.date, format: .relative(presentation: .named))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0) // the whole row takes the tap, not its words alone (#3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = file }
                    }
                    .contextMenu {
                        Button("Open", systemImage: "arrow.up.forward.app") { Task { _ = await studio.open(file) } }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = file }
                    }
                }
                if words.isEmpty && files.count > Self.latest {
                    Button(all ? "Show the Latest \(Self.latest)" : "Show All \(files.count) Presets") {
                        withAnimation(.snappy) { all.toggle() }
                    }
                    .font(.subheadline.weight(.medium))
                }
            } header: {
                Text(all || !find.isEmpty || studio.cardFiles.count <= Self.latest ? "On the Card" : "Latest on the Card")
            }

            Section {
                Button("Open File…", systemImage: "folder") { importing = true }
                    .keyboardShortcut("o", modifiers: .command)
                ShareLink(item: PresetFile(name: fileName(studio.preset.name), text: studio.text),
                          preview: SharePreview(fileName(studio.preset.name))) {
                    Label("Share This EQ", systemImage: "square.and.arrow.up")
                }
                Button("Copy", systemImage: "doc.on.doc") { studio.copyEQ() }
                Button("Paste", systemImage: "doc.on.clipboard") { pasting = true }
            } header: {
                Text("This EQ")
            } footer: {
                Text("Open file and Paste take a preset's text, as Equalizer APO, AutoEq and PEQdB write it, or a preset exported from Poweramp, with its Bass and Treble. So does a file dropped on the window.")
            }

            Section {
                ForEach(Export.all, id: \.self) { e in
                    Button { export(e) } label: {
                        Label { VStack(alignment: .leading, spacing: 2) { Text(e.title).foregroundStyle(.primary); Text(e.detail).font(.caption).foregroundStyle(.secondary) } }
                            icon: { Image(systemName: e.icon) }
                    }
                }
            } header: {
                Text("For other apps")
            } footer: {
                Text("The curve the Q2 plays, as other EQs take it.")
            }
        }
        .clearOfLiveStatus()
        .navigationTitle("Card")
        .settingsButton()
        .onAppear(perform: asked)
        .onChange(of: studio.cardAsked) { asked() }
        .sheet(isPresented: $pasting) { PasteSheet() }
        .fileExporter(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }), document: exportFile,
                      contentType: exportFile?.type ?? .plainText, defaultFilename: exportFile?.name) { result in
            if case .success = result, let f = exportFile { studio.say(["Saved \(f.name).", f.notes].filter { !$0.isEmpty }.joined(separator: " ")) }
            exportFile = nil
        }
        .task { await studio.loadCard() }
        .refreshable { await studio.loadCard() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count <= Poweramp.fileMax else {
                studio.tell("This preset couldn't be opened", "It's too big to be a preset.")
                return
            }
            let name = url.lastPathComponent.replacingOccurrences(of: #"\.json$"#, with: "", options: [.regularExpression, .caseInsensitive])
            studio.open(text: String(decoding: data, as: UTF8.self), name: nameOfFile(name), from: "from the file")
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

    /// The preset file the card would get, through the Files app's save sheet.
    private func saveToFiles() {
        exportFile = ExportFile(data: Data(studio.text.utf8), name: fileName(studio.preset.name), type: .plainText, notes: "")
    }

    private func askSave() {
        name = studio.preset.name.isEmpty ? EQ.fallbackName : studio.preset.name
        saving = true
    }

    /// ⌘S or ⌘O from another tab.
    private func asked() {
        switch studio.cardAsked {
        case "save": askSave()
        case "open": importing = true
        default: return
        }
        studio.cardAsked = nil
    }

    /// A file for another app, as the page names it: the name, the format, the rate.
    private func export(_ e: Export) {
        let p = studio.preset
        let base = String(fileName(p.name).dropLast(4))
        if e != .picture && !p.bands.contains(where: { $0.on && $0.gain != 0 }) {
            studio.say("No band changes the sound yet, so there is nothing to export.")
            return
        }
        let k = e.rate.map { r in (r / 1000).truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(r / 1000))k" : String(format: "%.1fk", r / 1000) } ?? ""
        switch e {
        case .wavelet:
            let out = Formats.wavelet(p)
            exportFile = ExportFile(data: Data(out.text.utf8), name: "\(base) Wavelet.txt", type: .plainText, notes: out.notes.joined(separator: " "))
        case .biquad48, .biquad96:
            let out = Formats.biquads(p, rate: e.rate!)
            exportFile = ExportFile(data: Data(out.text.utf8), name: "\(base) biquads \(k).txt", type: .plainText, notes: out.notes.joined(separator: " "))
        case .wav44, .wav48:
            let out = Formats.convolution(p, rate: e.rate!)
            exportFile = ExportFile(data: out.data, name: "\(base) \(k).wav", type: .wav, notes: out.notes.joined(separator: " "))
        case .picture:
            guard let png = GraphPicture.png(studio) else {
                studio.say("The picture couldn't be made.")
                return
            }
            exportFile = ExportFile(data: png, name: "\(base).png", type: .png, notes: "")
        }
    }

    private func save(replace: Bool) {
        Task {
            switch await studio.save(as: name, replace: replace) {
            case .saved:
                studio.buzz(.success)
                message = "Saved to the card's EQ folder."
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
        UIPasteboard.general.string = s
    }

    static func text() -> String? {
        UIPasteboard.general.string
    }
}

/// For other apps, as the page lists them.
enum Export: CaseIterable, Hashable {
    case wavelet, biquad48, biquad96, wav44, wav48, picture
    static let all = allCases
    var title: String {
        switch self {
        case .wavelet: "Wavelet"
        case .biquad48: "Biquads, 48 kHz"
        case .biquad96: "Biquads, 96 kHz"
        case .wav44: "Convolution, 44.1 kHz"
        case .wav48: "Convolution, 48 kHz"
        case .picture: "Picture of the graph"
        }
    }
    var detail: String {
        switch self {
        case .wavelet: "Its GraphicEQ, for Wavelet on Android"
        case .biquad48, .biquad96: "miniDSP's text, a list for each output"
        case .wav44, .wav48: "An impulse response (.wav) for a convolver"
        case .picture: "A .png of the curve, with its name"
        }
    }
    var icon: String {
        switch self {
        case .wavelet: "waveform"
        case .biquad48, .biquad96: "slider.horizontal.3"
        case .wav44, .wav48: "waveform.path"
        case .picture: "photo"
        }
    }
    var rate: Double? {
        switch self {
        case .biquad48, .wav48: 48000
        case .biquad96: 96000
        case .wav44: 44100
        default: nil
        }
    }
}

struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .wav, .png] }
    let data: Data
    let name: String
    let type: UTType
    let notes: String
    init(data: Data, name: String, type: UTType, notes: String) { (self.data, self.name, self.type, self.notes) = (data, name, type, notes) }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// The page's picture of the graph: the curve, its name and preamp, on a plain background.
enum GraphPicture {
    @MainActor static func png(_ studio: Studio) -> Data? {
        let view = GraphView(interactive: false, still: true).environment(studio).frame(width: 960, height: 540).environment(\.colorScheme, .light)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let cg = r.cgImage else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

/// Paste an EQ: its text, as Equalizer APO, AutoEq and PEQdB write it, or Poweramp's.
struct PasteSheet: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .onAppear { if text.isEmpty, let t = Clipboard.text() { text = String(t.prefix(Poweramp.fileMax)) } }
                        .font(.body.monospaced())
                        .frame(minHeight: 220)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("The EQ's text")
                } footer: {
                    Text("A preset's text, as Equalizer APO, AutoEq and PEQdB write it, or a preset exported from Poweramp.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Paste an EQ")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        if studio.open(text: String(text.prefix(Poweramp.fileMax)), name: "", from: "from the paste") == nil { dismiss() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}
