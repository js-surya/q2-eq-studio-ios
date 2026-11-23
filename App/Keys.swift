// SPDX-License-Identifier: GPL-3.0-only
// The keys, as EQ Studio's page has them (PEQdB Studio's where it has them): on a Mac, and on an iPad or
// iPhone with a keyboard. A key the focused field takes (typing, a table cell's arrows) never gets here.
import EQCore
import SwiftUI

extension Studio {
    /// The band a key acts on: the picked one, else the first.
    private var keyBand: Int? { band(selected) ?? (preset.bands.isEmpty ? nil : 0) }

    private func nudge(_ i: Int, _ field: String, _ up: Bool, _ fine: Bool) {
        let id = preset.bands[i].id
        selected = id
        let knob = Knob.of(preset.bands[i]) != nil
        let d: Double = up ? 1 : -1
        change("key:\(id):\(field)") { p in
            guard let k = p.bands.firstIndex(where: { $0.id == id }) else { return }
            switch field {
            case "freq": if !knob { p.bands[k].freq = min(max(p.bands[k].freq * pow(2, d / (fine ? 48 : 12)), EQ.freqMin), EQ.freqMax) }
            case "gain":
                let g = p.bands[k].gain + d * (fine ? 0.1 : 0.5)
                p.bands[k].gain = ((knob ? min(max(g, 0), Knob.maxGain) : min(max(g, -EQ.gainMax), EQ.gainMax)) * 100).rounded() / 100
            default: if !knob { p.bands[k].q = min(max(p.bands[k].q * pow(2, d / (fine ? 24 : 6)), EQ.qMin), EQ.qMax) }
            }
        }
    }

    /// A key pressed with nothing else taking it: true when it did something.
    func key(_ key: String, shift: Bool, again: Bool, tab: (Int) -> Void) -> Bool {
        let once = !again
        switch key {
        case "1", "2", "3", "4": tab(Int(key)! - 1)
        case "?": if once { showKeys = true }
        case "/": searchAsked = UUID()
        case " ": if once { inspect.toggle() }
        case "q", "w", "e":
            guard let i = keyBand else { return false }
            if let knob = Knob.of(preset.bands[i]) {
                if once { say("\(knob.title) is Poweramp's knob: it stays a shelf.") }
                break
            }
            let id = preset.bands[i].id
            change { p in if let k = p.bands.firstIndex(where: { $0.id == id }) { p.bands[k].type = key == "q" ? .peak : key == "w" ? .lowShelf : .highShelf } }
        case "r", "t": if once { say("The Q2's EQ has peaks and shelves, and no high- or low-pass.") }
        case "s":
            guard once, let i = keyBand else { return false }
            let id = preset.bands[i].id
            change { p in if let k = p.bands.firstIndex(where: { $0.id == id }) { p.bands[k].on.toggle() } }
        case "d", "delete", "backspace":
            guard once, let i = keyBand else { return false }
            deleteBand(preset.bands[i].id)
        case "a", "+":
            if once { addBand() }
        case "b":
            guard once else { break }
            let anyOn = preset.bands.contains { $0.on }
            change { p in for k in p.bands.indices { p.bands[k].on = !anyOn } }
        case "v": if once { showEachBand.toggle() }
        case "f": if once { zoom = nil }
        case "c":
            guard once else { break }
            if live.on { setMode(live.mode != "peq") } else { say("EQ on and off is for a Q2 with live EQ.") }
        case "[", "]":
            guard !preset.bands.isEmpty else { return false }
            let now = band(selected) ?? 0
            selected = preset.bands[(now + (key == "]" ? 1 : preset.bands.count - 1)) % preset.bands.count].id
        case "left", "right", "up", "down", ",", ".", "<", ">":
            guard let i = keyBand else { return false }
            let field = key == "left" || key == "right" ? "freq" : key == "up" || key == "down" ? "gain" : "q"
            nudge(i, field, ["right", "up", ".", ">"].contains(key), shift)
        case "escape":
            if inspect { inspect = false } else { return false }
        default: return false
        }
        return true
    }
}

/// The keys and the mouse, as the page's ? lists them.
struct KeysSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let keys: [(String, String)] = [
        ("1, 2, 3, 4", "EQ, Search (the presets), Response, Card; ⌘1 to ⌘4 even while typing"),
        ("Space", "Inspect the curve: a line at the pointer, and the gain there"),
        ("Q, W, E", "The picked band: peak, low shelf, high shelf"),
        ("S", "That band on or off"),
        ("D, Delete", "Delete it"),
        ("A, +", "Add a band"),
        ("[, ]", "Pick the band before, after"),
        ("←, →, ↑, ↓", "The band's frequency and gain (with Shift, finer)"),
        (",  .", "The band's Q, wider or narrower"),
        ("B", "Every band off, or on"),
        ("V", "Each band's own curve"),
        ("C", "EQ on or off on the Q2"),
        ("F", "Fit the curve to the graph, after the wheel zoomed it"),
        ("/", "Search the presets"),
        ("⌘Z, ⇧⌘Z", "Undo, redo"),
        ("⇧⌘C, ⇧⌘V", "Copy the EQ as text, paste one"),
        ("⌘S, ⌘O", "Save to the card, open a file"),
        ("Esc", "Inspect off"),
        ("?", "These keys, and the mouse's"),
    ]
    private let mouse: [(String, String)] = [
        ("Drag a dot", "Move its band"),
        ("Drag the curve", "Move the band that shapes it there"),
        ("Wheel on a dot", "Its Q (with Shift, finer)"),
        ("Wheel elsewhere", "Zoom the dB scale"),
        ("Press the 0 dB line", "Add a band there, and drag it"),
        ("Double-click", "Add a band"),
        ("A file dropped on the window", "Open it"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Keys") { ForEach(keys, id: \.0) { row($0) } }
                Section("The mouse") { ForEach(mouse, id: \.0) { row($0) } }
            }
            .navigationTitle("Keyboard and Mouse")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    private func row(_ r: (String, String)) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(r.0).font(.body.monospaced().weight(.semibold)).frame(width: 150, alignment: .leading)
            Text(r.1).foregroundStyle(.secondary)
        }
    }
}
