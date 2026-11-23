// SPDX-License-Identifier: GPL-3.0-only
// Reading and writing a preset's text, the Equalizer APO format the Q2 imports: web/eq.js's parse
// and serialize, which take and refuse what peq_parse does, in its words.
import Foundation

public struct ParseError: Error, Equatable, Sendable {
    public let line: Int
    public let reason: String
    public var message: String { "Line \(line): \(reason)" }
}

/// peq_number: decimal only, a comma as the mark, the token used whole. nil if it is not one. The
/// C library's %lf also takes an exponent with no digits, as in 355E, and reads it as 355.
func number(_ token: String) -> Double? {
    let text = token.replacingOccurrences(of: ",", with: ".")
    guard let m = text.wholeMatch(of: /([+-]?(?:\d+\.?\d*|\.\d+))(?:[eE][+-]?\d*)?/) else { return nil }
    let endsInDigit = text.last.map { $0.isASCII && $0.isNumber } ?? false
    let value = Double(endsInDigit ? text : String(m.1))
    return value.flatMap { $0.isFinite ? $0 : nil }
}

private func between(_ v: Double, _ lo: Double, _ hi: Double) -> Bool { v >= lo && v <= hi }

/// A line's words, with a colon always a word of its own, and # ending the line. nil past the limit.
func words(_ line: [Unicode.Scalar]) -> [String]? {
    var out: [String] = []
    let blank: Set<Unicode.Scalar> = [" ", "\t", "\r"]
    var at = 0
    while at < line.count && line[at] != "#" {
        if blank.contains(line[at]) { at += 1; continue }
        if out.count == EQ.tokensMax { return nil }
        if line[at] == ":" { out.append(":"); at += 1; continue }
        let start = at
        while at < line.count && !blank.contains(line[at]) && line[at] != ":" && line[at] != "#" { at += 1 }
        out.append(String(String.UnicodeScalarView(line[start..<at])))
        if at < line.count && line[at] == ":" {
            if out.count == EQ.tokensMax { return nil }
            out.append(":")
            at += 1
        } else if at < line.count && line[at] == "#" {
            break
        }
    }
    return out
}

private func validBand(_ b: Band) -> Bool {
    between(b.freq, EQ.freqMin, EQ.freqMax) && between(b.gain, -EQ.gainMax, EQ.gainMax) && between(b.q, EQ.qMin, EQ.qMax)
}

private func bytes(_ s: some Collection<Unicode.Scalar>) -> Int { s.reduce(0) { $0 + UTF8.width($1) } }

/// The preset with the values as read, or where and why the Q2 would refuse it.
public func parse(_ text: String, name: String = "") -> Result<Preset, ParseError> {
    func fail(_ line: Int, _ reason: String) -> Result<Preset, ParseError> { .failure(ParseError(line: line, reason: reason)) }
    if text.utf8.count > EQ.fileMax { return fail(1, "file exceeds 16384 bytes") }
    var scalars = Array(text.unicodeScalars)
    if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
    var lines = scalars.split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
    if lines.last?.isEmpty == true { lines.removeLast() } // the end of the last line, not a line after it

    var preset = Preset(name: name)
    var side: [Channel: Double] = [.left: 0, .right: 0]
    var scope = Channel.all
    var preampLine = 0

    for (index, raw) in lines.enumerated() {
        let line = index + 1
        // The Q2 reads a line a byte at a time, so whichever comes first is what it reports.
        let tooLong = bytes(raw) > EQ.lineMax
        if let nul = raw.firstIndex(of: "\0"), !tooLong || bytes(raw[..<nul]) < EQ.lineMax {
            return fail(line, "embedded NUL")
        }
        if tooLong { return fail(line, "line exceeds 512 bytes") }
        guard let t = words(raw) else { return fail(line, "unsupported filter form") }
        let n = t.count
        if n == 0 { continue }
        func at(_ i: Int) -> String? { i < n ? t[i] : nil }

        if t[0] == "Preamp" {
            guard n == 4, t[1] == ":", t[3] == "dB" else { return fail(line, "expected Preamp: <gain> dB") }
            guard let gain = number(t[2]), between(gain, EQ.preampMin, EQ.preampMax) else {
                return fail(line, "preamp outside -60..24 dB or invalid number")
            }
            if scope == .all { preset.preamp += gain } else { side[scope, default: 0] += gain }
            preampLine = line
            continue
        }

        if t[0] == "Channel" {
            guard n >= 3, t[1] == ":" else { return fail(line, "expected Channel: L, R or all") }
            var (left, right) = (false, false)
            for word in t[2...] {
                switch word {
                case "L": left = true
                case "R": right = true
                case "all": left = true; right = true
                default: return fail(line, "only channels L, R and all are supported")
                }
            }
            scope = left && right ? .all : left ? .left : .right
            continue
        }

        if t[0] != "Filter" { return fail(line, "unsupported command") }
        var k = 1
        if n > 1 && t[1] != ":" {
            if !t[1].allSatisfy({ $0.isASCII && $0.isNumber }) { return fail(line, "invalid filter label") }
            k += 1
        }
        if n <= k || t[k] != ":" { return fail(line, "expected Filter [number]:") }
        k += 1
        if n - k == 2 && at(k + 1) == "None" { continue } // REW's and APO's empty slot
        if n - k != 8 && n - k != 10 { return fail(line, "unsupported filter form") }

        var band = Band(channel: scope, freq: 0, gain: 0, q: 0.7071067811865476)
        if t[k] == "OFF" { band.on = false } else if t[k] != "ON" { return fail(line, "expected ON or OFF") }
        k += 1
        let kind = t[k]
        switch kind {
        case "PK", "PEQ": band.type = .peak
        case "LS", "LSC": band.type = .lowShelf
        case "HS", "HSC": band.type = .highShelf
        default: return fail(line, "unsupported filter type")
        }
        let corner = kind.count == 2 // APO: LS and HS give a corner, LSC and HSC the centre
        k += 1
        if t[k] != "Fc" || t[k + 2] != "Hz" || t[k + 3] != "Gain" || t[k + 5] != "dB" {
            return fail(line, "expected Fc <Hz> Hz Gain <dB> dB")
        }
        guard let freq = number(t[k + 1]), let gain = number(t[k + 4]) else {
            return fail(line, "invalid frequency or gain number")
        }
        band.freq = freq
        band.gain = gain
        k += 6
        let hasQ = k < n
        if hasQ {
            guard t[k] == "Q", let q = at(k + 1).flatMap(number) else { return fail(line, "expected Q <number>") }
            band.q = q
        } else if band.type == .peak {
            return fail(line, "peaking filter requires Q")
        }

        if band.type != .peak && validBand(band) {
            // As Equalizer APO: no Q means slope 0.9 at Fc, and LS or HS with a Q shift the corner to the centre.
            let a = pow(10, band.gain / 40)
            let ab = a + 1 / a
            if !hasQ {
                band.q = 1 / (ab * (1 / 0.9 - 1) + 2).squareRoot()
            } else if corner {
                let shift = pow(10, abs(band.gain) / 80 * ((1 / (band.q * band.q) - 2) / ab + 1))
                band.freq = band.type == .lowShelf ? band.freq * shift : band.freq / shift
                band.freq = clamp(band.freq, EQ.freqMin, EQ.freqMax) // past the range is clamped, not refused
            }
        }
        if !validBand(band) {
            if !band.on { continue } // APO ignores OFF filters, and exporters fill blank slots with Fc 0 Q 0
            return fail(line, "range: 20..20000 Hz, -24..24 dB, Q 0.1..10")
        }
        if preset.bands.count == EQ.maxBands { return fail(line, "more than 30 bands") }
        preset.bands.append(band)
    }

    // Each side's preamp becomes the louder one's common preamp plus a balance turning the other down.
    let (l, r) = (side[.left] ?? 0, side[.right] ?? 0)
    preset.preamp += max(l, r)
    preset.balance = r - l
    if !between(preset.preamp, EQ.preampMin, EQ.preampMax) { return fail(preampLine, "summed preamp outside -60..24 dB") }
    if !between(preset.balance, -EQ.balanceMax, EQ.balanceMax) {
        return fail(preampLine, "L/R preamp differ by more than 12 dB")
    }
    preset.auto = preampLine == 0
    return .success(preset)
}

/// LSC and HSC always, so the Q2 takes the frequency as it stands here. A preset with balance needs
/// Preamp lines, so Auto is written as its 48 kHz figure.
public func serialize(_ preset: Preset) -> String {
    let clean = normalize(preset)
    var lines: [String] = []
    if !clean.auto || clean.balance != 0 {
        lines.append("Preamp: \(decimal(clean.auto ? autoPreamp(clean) : clean.preamp, 2)) dB")
    }
    if clean.balance != 0 {
        lines += ["Channel: L", "Preamp: \(decimal(min(-clean.balance, 0), 2)) dB"]
        lines += ["Channel: R", "Preamp: \(decimal(min(clean.balance, 0), 2)) dB", "Channel: all"]
    }
    var scope = Channel.all
    for (index, band) in clean.bands.enumerated() {
        if band.channel != scope {
            scope = band.channel
            lines.append("Channel: \(scope.rawValue)")
        }
        lines.append("Filter \(index + 1): \(band.on ? "ON" : "OFF") \(band.type.rawValue) Fc \(decimal(band.freq, 2)) Hz "
            + "Gain \(decimal(band.gain, 2)) dB Q \(decimal(band.q, 3))")
    }
    return lines.joined(separator: "\n") + "\n"
}
