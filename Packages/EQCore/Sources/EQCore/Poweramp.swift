// SPDX-License-Identifier: GPL-3.0-only
// The presets Poweramp exports, as EQ Studio's web/poweramp.js reads them (the knobs are Knobs.swift).
//
// Poweramp exports a preset as JSON: [{ name, preamp, parametric, bands: [{ type, channels, frequency, q,
// gain, color }] }], gain and preamp in dB. Every export seen opens with the knobs, type 0 Bass and type 1
// Treble, at 90 Hz, Q 0.8 and 10 kHz, Q 0.6 and 0 dB while unturned. 3, 4 and 5 are its peak, low shelf and
// high shelf, the filters the Q2 has. 2 is in presets REW made and in graphic EQ ones, with a gain and a Q:
// read here as a peak. None of this is documented; it is read off exports.
import Foundation

public enum Poweramp {
    public static let fileMax = 1 << 20 // an export of every preset is still far under this
    static let types: [Int: FilterType] = [0: .lowShelf, 1: .highShelf, 2: .peak, 3: .peak, 4: .lowShelf, 5: .highShelf]
    static let notPoweramp = "This isn't a preset Poweramp exported."

    public struct Read: Sendable { public let preset: Preset; public let notes: [String] }

    static func hz(_ f: Double) -> String { "\(Int(f.rounded(.toNearestOrAwayFromZero))) Hz" } // Poweramp's are whole

    static func list(_ items: [String]) -> String {
        items.count < 3 ? items.joined(separator: " and ") : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    static func bandsAt(_ freqs: [Double]) -> String {
        freqs.count > 3 ? "\(freqs.count) bands" : "\(freqs.count == 1 ? "The band" : "The bands") at \(list(freqs.map(hz)))"
    }

    /// A JSON value as JS's Number() takes it: a number, a numeric string, a bool; else NaN.
    static func num(_ v: Any?) -> Double {
        switch v {
        case let n as NSNumber: return n.doubleValue
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? 0 : Double(t) ?? .nan
        case is NSNull: return 0
        default: return .nan
        }
    }

    /// The preset with the values as read, notes saying what changed on the way, or why it isn't one.
    /// name is for a preset without one.
    public static func read(_ text: String, name: String = "") -> Result<Read, ParseError> {
        func fail(_ why: String) -> Result<Read, ParseError> { .failure(ParseError(line: 0, reason: why)) }
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        guard let data = try? JSONSerialization.jsonObject(with: Data(t.utf8), options: [.fragmentsAllowed]) else { return fail(notPoweramp) }
        let presets: [Any] = (data as? [Any]) ?? [data]
        guard let first = presets.first as? [String: Any], let rows = first["bands"] as? [Any] else { return fail(notPoweramp) }
        if let p = first["parametric"] as? Bool, p == false {
            return fail("This preset is from Poweramp's graphic EQ, and EQ Studio reads its parametric ones. "
                + "Turn on Poweramp's parametric EQ, then export the preset again.")
        }

        var notes: [String] = []
        var bands: [Band] = []
        var (sided, typeTwo, wide, unread) = ([Double](), [Double](), [Double](), 0)
        for item in rows {
            let row = item as? [String: Any]
            let code = num(row?["type"])
            let (freq, gain, q) = (num(row?["frequency"]), num(row?["gain"]), num(row?["q"]))
            guard code.isFinite, code == code.rounded(), let type = types[Int(code)], gain.isFinite, freq > 0, q > 0 else {
                unread += 1
                continue
            }
            if code <= 1 && gain == 0 { continue } // an unturned knob
            if num(row?["channels"] ?? 0) != 0 {
                sided.append(freq)
                continue
            }
            if code == 2 { typeTwo.append(freq) }
            if freq < EQ.freqMin || freq > EQ.freqMax || q < EQ.qMin || q > EQ.qMax || abs(gain) > EQ.gainMax { wide.append(freq) }
            let enabled = (row?["enabled"] as? Bool) ?? true
            bands.append(Band(on: enabled, type: type, freq: freq, gain: gain, q: q))
        }

        if presets.count > 1 { notes.append("The file holds \(presets.count) presets. This is the first.") }
        if !sided.isEmpty {
            let one = sided.count == 1
            notes.append("\(bandsAt(sided)) \(one ? "is" : "are") for one side only, and the file doesn't say which, so \(one ? "it's" : "they're") left out.")
        }
        if unread > 0 {
            notes.append("\(unread == 1 ? "A band" : "\(unread) bands") couldn't be read, so \(unread == 1 ? "it's" : "they're") left out.")
        }
        if !typeTwo.isEmpty {
            let one = typeTwo.count == 1
            notes.append("\(bandsAt(typeTwo)) \(one ? "is" : "are") of a kind Poweramp's file doesn't name. \(one ? "It's read as a peak" : "They're read as peaks"), and may not sound quite as in Poweramp.")
        }
        if !wide.isEmpty {
            let one = wide.count == 1
            notes.append("\(bandsAt(wide)) \(one ? "goes" : "go") past what the Q2 takes, 20 Hz to 20 kHz and Q 0.1 to 10, so \(one ? "it's" : "they're") brought inside it.")
        }
        if bands.count > EQ.maxBands { notes.append("The Q2 takes \(EQ.maxBands) bands, so the last \(bands.count - EQ.maxBands) are left out.") }

        let preamp = num(first["preamp"])
        let own = first["name"] as? String
        let preset = Preset(name: own.map { cleanName($0).isEmpty ? name : $0 } ?? name, auto: false,
                            preamp: preamp.isFinite ? preamp : 0, balance: 0, bands: bands)
        return .success(Read(preset: preset, notes: notes))
    }

    /// Whether a file's text is JSON, so one for read rather than parse: a preset's text never opens with a bracket.
    public static func isJSON(_ text: String) -> Bool {
        text.firstMatch(of: /^\u{FEFF}?\s*[\[{]/) != nil
    }
}
