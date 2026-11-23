// SPDX-License-Identifier: GPL-3.0-only
// A preset and its bands, as EQ Studio's web/eq.js has them (from tyleree's Q2 Theme Studio, GPL-3.0).
import Foundation

/// The Q2's limits, peq.c's.
public enum EQ {
    public static let maxBands = 30
    public static let fileMax = 16384
    static let lineMax = 512
    static let tokensMax = 16
    public static let freqMin = 20.0
    public static let freqMax = 20000.0
    public static let gainMax = 24.0
    public static let qMin = 0.1
    public static let qMax = 10.0
    public static let preampMin = -60.0
    public static let preampMax = 24.0
    public static let balanceMax = 12.0
    static let nameBytes = 60 // the Q2's editor keeps 63 bytes of a preset's name
    public static let autoRate = 48000.0 // the rate the Q2's editor shows Auto's figure for
    public static let defaultFreqs: [Double] = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let defaultQ = 1.41
    public static let fallbackName = "My EQ"
}

public enum FilterType: String, CaseIterable, Sendable, Codable {
    case peak = "PK", lowShelf = "LSC", highShelf = "HSC"
}

public enum Channel: String, CaseIterable, Sendable, Codable {
    case all, left = "L", right = "R"
}

public struct Band: Identifiable, Sendable, Codable {
    /// For the screen only: two bands are equal when their values are.
    public var id = UUID()
    public var on: Bool
    public var channel: Channel
    public var type: FilterType
    public var freq: Double
    public var gain: Double
    public var q: Double

    public init(on: Bool = true, channel: Channel = .all, type: FilterType = .peak, freq: Double = 1000,
                gain: Double = 0, q: Double = EQ.defaultQ) {
        (self.on, self.channel, self.type, self.freq, self.gain, self.q) = (on, channel, type, freq, gain, q)
    }
}

extension Band: Equatable {
    public static func == (a: Band, b: Band) -> Bool {
        a.on == b.on && a.channel == b.channel && a.type == b.type && a.freq == b.freq && a.gain == b.gain && a.q == b.q
    }
}

/// auto: no Preamp line, so the Q2 works the preamp out for each song's rate. balance: dB, above 0
/// turns the left channel down.
public struct Preset: Equatable, Sendable, Codable {
    public var name: String
    public var auto: Bool
    public var preamp: Double
    public var balance: Double
    public var bands: [Band]

    public init(name: String = "", auto: Bool = true, preamp: Double = 0, balance: Double = 0, bands: [Band] = []) {
        (self.name, self.auto, self.preamp, self.balance, self.bands) = (name, auto, preamp, balance, bands)
    }

    /// The ten bands the Q2's Reset gives.
    public static func flat(name: String = "") -> Preset {
        Preset(name: name, bands: EQ.defaultFreqs.map { Band(freq: $0) })
    }
}

// MARK: - Numbers as the page writes them

/// +value.toFixed(digits): halves away from zero.
func round(_ value: Double, _ digits: Int) -> Double {
    let m = pow(10, Double(digits))
    return (value * m).rounded(.toNearestOrAwayFromZero) / m
}

func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

func finite(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }

/// A plain decimal, its trailing zeros gone: the Q2 reads exponents too, but no other tool needs to meet one.
public func decimal(_ value: Double, _ digits: Int) -> String {
    var r = round(value, digits)
    if r == 0 { r = 0 } // no -0
    var text = String(format: "%.\(digits)f", r)
    if digits > 0, text.contains(".") {
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
    }
    return text == "-0" ? "0" : text
}

// MARK: - Names

private func isReserved(_ name: String) -> Bool {
    name.wholeMatch(of: /(con|prn|aux|nul|com[1-9]|lpt[1-9])/.ignoresCase()) != nil
}

private func isSpace(_ s: Unicode.Scalar) -> Bool { s.properties.isWhitespace || s == "\u{FEFF}" }

/// A name the card can hold, as the Q2's Rename allows: FAT's characters out, and no leading dot.
public func cleanName(_ text: String) -> String {
    var scalars = text.unicodeScalars.filter { s in
        let v = s.value
        if v <= 0x1F || (0x7F...0x9F).contains(v) || v == 0x2028 || v == 0x2029 { return false }
        return !"/\\:*?\"<>|".unicodeScalars.contains(s)
    }
    while let f = scalars.first, isSpace(f) { scalars.removeFirst() }
    while let l = scalars.last, isSpace(l) { scalars.removeLast() }
    while let f = scalars.first, f == "." || isSpace(f) { scalars.removeFirst() }
    var name = String(String.UnicodeScalarView(scalars))
    while name.utf8.count > EQ.nameBytes {
        var u = name.unicodeScalars
        u.removeLast()
        name = String(u)
    }
    var u = Array(name.unicodeScalars)
    while let l = u.last, l == "." || isSpace(l) { u.removeLast() }
    return String(String.UnicodeScalarView(u))
}

/// The preset's file on the card's EQ folder.
public func fileName(_ name: String) -> String {
    let clean = cleanName(name).isEmpty ? EQ.fallbackName : cleanName(name)
    return (isReserved(clean) ? "EQ \(clean)" : clean) + ".txt"
}

public func nameOfFile(_ file: String) -> String {
    var base = file
    if let cut = base.lastIndex(where: { $0 == "/" || $0 == "\\" }) { base = String(base[base.index(after: cut)...]) }
    if base.lowercased().hasSuffix(".txt") { base.removeLast(4) }
    return cleanName(base)
}

// MARK: - Legal values

public func normalize(_ band: Band) -> Band {
    var b = band
    b.freq = clamp(round(finite(band.freq, 1000), 2), EQ.freqMin, EQ.freqMax)
    b.gain = clamp(round(finite(band.gain, 0), 2), -EQ.gainMax, EQ.gainMax)
    b.q = clamp(round(finite(band.q, EQ.defaultQ), 3), EQ.qMin, EQ.qMax)
    return b
}

/// The preset with every value legal and at the file's precision.
public func normalize(_ preset: Preset) -> Preset {
    Preset(name: cleanName(preset.name), auto: preset.auto,
           preamp: clamp(round(finite(preset.preamp, 0), 2), EQ.preampMin, EQ.preampMax),
           balance: clamp(round(finite(preset.balance, 0), 2), -EQ.balanceMax, EQ.balanceMax),
           bands: preset.bands.prefix(EQ.maxBands).map(normalize))
}
