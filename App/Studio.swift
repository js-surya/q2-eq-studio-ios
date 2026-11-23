// SPDX-License-Identifier: GPL-3.0-only
// The app's state: the preset being edited, its undo history, what the Q2 plays and how the live EQ
// is going, AutoEq's catalogue and the card's EQ folder. Live EQ works as EQ Studio's page does
// (web/app.js): the preset as it stands goes to the Q2 unless the Q2 already has it, one request at
// a time, the newest replacing any still waiting.
import EQCore
import Foundation
import Observation

@MainActor @Observable
final class Studio {
    // MARK: The Q2
    var link: Q2Link? {
        didSet { client = link.map(Q2Client.init) }
    }
    private(set) var client: Q2Client?

    init() {
        link = LinkStore.load()
        #if DEBUG
        // For the simulator, which has no camera: EQS_LINK=<the QR code's link> signs in at launch.
        if let s = ProcessInfo.processInfo.environment["EQS_LINK"], let l = Q2Link(scanned: s) { link = l }
        #endif
        client = link.map(Q2Client.init)
        if let data = try? Data(contentsOf: Studio.catalogueFile) { catalogue = try? Catalogue(json: data) }
    }

    func connect(_ link: Q2Link) {
        LinkStore.save(link)
        self.link = link
        live = LiveState()
        history = []
        future = []
        Task { await readState(first: true) }
    }

    func disconnect() {
        LinkStore.forget()
        link = nil
        live = LiveState()
        cardFiles = []
    }

    // MARK: The preset and its history

    private(set) var preset = Preset.flat()
    var selected: Band.ID?
    var showEachBand = false

    private var history: [Preset] = []
    private var future: [Preset] = []
    private var lastKey: String?
    private var lastAt = Date.distantPast
    private static let historyMax = 200

    var canUndo: Bool { !history.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// An edit: one undo step, unless it carries the same key as the edit just before, within a
    /// moment (a drag, a slider, typing), which then shares that step.
    func change(_ key: String? = nil, _ edit: (inout Preset) -> Void) {
        var next = preset
        edit(&next)
        if next == preset { return }
        let now = Date()
        if key == nil || key != lastKey || now.timeIntervalSince(lastAt) > 1.0 {
            history.append(preset)
            if history.count > Studio.historyMax { history.removeFirst() }
            future = []
        }
        (lastKey, lastAt) = (key, now)
        preset = next
        send()
    }

    /// A whole preset in place of this one (a pick from AutoEq, a file): Undo takes it back.
    func replace(with next: Preset) {
        change(nil) { $0 = next }
        selected = nil
    }

    func undo() {
        guard let last = history.popLast() else { return }
        future.append(preset)
        preset = last
        lastKey = nil
        send()
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(preset)
        preset = next
        lastKey = nil
        send()
    }

    func band(_ id: Band.ID?) -> Int? { id.flatMap { id in preset.bands.firstIndex { $0.id == id } } }

    func addBand(freq: Double = 1000, gain: Double = 0) {
        guard preset.bands.count < EQ.maxBands else { return }
        let b = Band(freq: freq, gain: gain)
        change { $0.bands.append(b) }
        selected = b.id
    }

    func deleteBand(_ id: Band.ID) {
        change { $0.bands.removeAll { $0.id == id } }
        if selected == id { selected = nil }
    }

    /// The text the Q2 and the card take, as a file the page would save.
    var text: String { serialize(preset) }
    var warnings: [String] { EQCore.warnings(preset) }

    // MARK: Live EQ

    struct LiveState {
        var known = false // the Q2 answered at least once
        var local = false // this Q2 Pod can't take an EQ: an editor only
        var on = false // it takes the EQ live
        var mode: String? // what plays: off, 3eq or peq
        var busy = false
        var sending = false // "Sending…", held a moment after the last answer
        var error: String?
        var retry: (@MainActor () -> Void)?
    }

    private enum Item { case eq(String), mode(Bool) }

    var live = LiveState()
    private var queue: [Item] = []
    private var sent: String?
    private var calm: Task<Void, Never>?

    var eqOn: Bool { live.mode == "peq" }

    /// The preset as it stands goes to the Q2, unless that is what it has. A preset plays at once,
    /// so it replaces anything waiting, an EQ off included.
    private func send() {
        guard live.on else { return }
        let t = serialize(preset)
        if t == sent { return }
        sent = t
        live.mode = "peq"
        queue = [.eq(t)]
        pump()
    }

    private func resend() {
        sent = nil
        send()
    }

    /// The EQ off or on on the Q2, after any preset still waiting.
    func setMode(_ on: Bool) {
        guard live.on else { return }
        live.mode = on ? "peq" : "off"
        queue.removeAll { if case .mode = $0 { true } else { false } }
        queue.append(.mode(on))
        pump()
    }

    private func pump() {
        guard !live.busy, !queue.isEmpty, let client else { return }
        let item = queue.removeFirst()
        live.busy = true
        live.sending = true
        calm?.cancel()
        Task {
            var failure: String?
            do {
                let r: SendResult
                switch item {
                case .eq(let t): r = try await client.putEQ(t)
                case .mode(let on): r = try await client.putMode(on: on)
                }
                if !r.ok {
                    let why = r.error ?? ""
                    failure = why.range(of: #"^line \d"#, options: [.regularExpression, .caseInsensitive]) != nil
                        ? "The Q2 didn't take it: \(why)" : (why.isEmpty ? "The Q2 didn't take it." : why)
                } else if queue.isEmpty, let mode = r.mode {
                    live.mode = mode
                }
            } catch Q2Error.local {
                goLocal()
            } catch {
                failure = error.localizedDescription
            }
            live.busy = false
            if let failure, queue.isEmpty {
                switch item {
                case .eq: setError(failure) { [weak self] in self?.resend() }
                case .mode(let on): setError(failure) { [weak self] in self?.setMode(on) }
                }
            } else if failure == nil {
                clearError()
            }
            if queue.isEmpty {
                calm = Task {
                    try? await Task.sleep(for: .milliseconds(350)) // so a drag doesn't flicker
                    if !Task.isCancelled { live.sending = false }
                }
            }
            pump()
        }
    }

    private func setError(_ text: String, retry: (@MainActor () -> Void)?) {
        live.error = text
        live.retry = retry
    }

    private func clearError() {
        live.error = nil
        live.retry = nil
    }

    private func goLocal() {
        live.local = true
        live.on = false
        live.mode = nil
        queue = []
        sent = nil
        clearError()
    }

    /// What the Q2 has. The first time it opens with the Q2's EQ; later, a change made on the Q2
    /// while this device was away replaces this one's, unless an edit is on its way.
    func readState(first: Bool = false, moved: Bool = false) async {
        guard let client else { return }
        let state: Q2State
        do {
            state = try await client.state()
        } catch {
            if !moved, let e = error as? Q2Error, e == .unreachable || e == .timeout, await moveToAnotherAddress() {
                await readState(first: first, moved: true)
                return
            }
            live.known = true
            setError(error.localizedDescription) { [weak self] in Task { await self?.readState(first: first) } }
            return
        }
        live.known = true
        if !state.live {
            goLocal()
            return
        }
        live.local = false
        live.on = true
        if live.busy || !queue.isEmpty { return }
        live.mode = state.mode
        if let e = state.error {
            setError(e) { [weak self] in Task { await self?.readState(first: first) } }
        } else {
            clearError()
        }
        if let text = state.preset { take(text, first: first) }
        if sent == nil { sent = serialize(preset) }
    }

    /// This Q2 at another address it was reached at before (Wi-Fi or Tailscale), if one answers now.
    private func moveToAnotherAddress() async -> Bool {
        guard let link else { return false }
        for base in LinkStore.addresses where base != link.base {
            let other = Q2Link(base: base, key: link.key)
            if (try? await Q2Client(link: other).state()) != nil {
                LinkStore.save(other)
                self.link = other
                return true
            }
        }
        return false
    }

    var addresses: [URL] { LinkStore.addresses }

    /// The Q2's PEQ, as this device's preset, keeping the name; the first time without an undo step.
    private func take(_ text: String, first: Bool) {
        switch parse(text) {
        case .failure(let e):
            setError("The Q2's EQ couldn't be read here: \(e.message).", retry: nil)
        case .success(let p):
            var theirs = normalize(p)
            theirs.name = preset.name
            sent = serialize(theirs)
            if serialize(preset) == sent { return }
            if first || history.isEmpty {
                preset = theirs
            } else {
                history.append(preset)
                future = []
                preset = theirs
            }
        }
    }

    // MARK: AutoEq's presets

    var catalogue: Catalogue?
    var catalogueError: String?
    var catalogueLoading = false

    private static var catalogueFile: URL {
        URL.cachesDirectory.appending(path: "presets.json")
    }

    func loadCatalogue() async {
        guard let client, !catalogueLoading else { return }
        catalogueLoading = true
        defer { catalogueLoading = false }
        do {
            let data = try await client.presets()
            let fresh = try Catalogue(json: data)
            catalogue = fresh
            catalogueError = nil
            try? data.write(to: Studio.catalogueFile)
        } catch {
            if catalogue == nil { catalogueError = error.localizedDescription }
        }
    }

    /// A preset from AutoEq, under its headphone's name.
    func apply(_ entry: Catalogue.Entry) {
        guard case .success(let p) = parse(entry.text, name: cleanName(entry.name)) else { return }
        replace(with: normalize(p))
    }

    // MARK: The card's EQ folder

    var cardFiles: [CardFile] = []
    var cardError: String?
    var cardLoading = false

    func loadCard() async {
        guard let client else { return }
        cardLoading = true
        defer { cardLoading = false }
        do {
            cardFiles = try await client.cardList()
            cardError = nil
        } catch {
            cardError = error.localizedDescription
        }
    }

    /// Opens a preset from the card; nil when it opened, else why not.
    func open(_ file: CardFile) async -> String? {
        guard let client else { return Q2Error.unreachable.localizedDescription }
        do {
            return open(text: try await client.cardGet(file.file), name: file.name)
        } catch {
            return error.localizedDescription
        }
    }

    /// A preset's text, from the card, a file or the clipboard; nil when it opened, else why not.
    func open(text: String, name: String) -> String? {
        switch parse(text, name: cleanName(name)) {
        case .failure(let e): return "That isn't a preset the Q2 can take. \(e.message)."
        case .success(let p):
            replace(with: normalize(p))
            return nil
        }
    }

    enum SaveOutcome { case saved, taken, failed(String) }

    func save(as name: String, replace: Bool = false) async -> SaveOutcome {
        guard let client else { return .failed(Q2Error.unreachable.localizedDescription) }
        let clean = cleanName(name)
        if clean != preset.name { change { $0.name = clean } }
        do {
            guard try await client.cardPut(fileName(clean), text: text, replace: replace) else { return .taken }
            await loadCard()
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func delete(_ file: CardFile) async -> String? {
        guard let client else { return Q2Error.unreachable.localizedDescription }
        do {
            try await client.cardDelete(file.file)
            cardFiles.removeAll { $0.id == file.id }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
