// SPDX-License-Identifier: GPL-3.0-only
// Bass and Treble, Poweramp's knobs, as EQ Studio's web/poweramp.js has them: each a shelf band of its
// own, known by its type, frequency and Q, so it lasts through a file and the Q2 as any band does.

public enum Knob: String, CaseIterable, Sendable {
    case bass, treble

    public static let maxGain = 15.0 // dB: Poweramp's knobs boost only, up to its EQ's most

    public var title: String { self == .bass ? "Bass" : "Treble" }
    public var type: FilterType { self == .bass ? .lowShelf : .highShelf }
    public var freq: Double { self == .bass ? 90 : 10000 }
    public var q: Double { self == .bass ? 0.8 : 0.6 }

    /// The knob a band is, if any. Bands are compared as normalize leaves them.
    public static func of(_ band: Band) -> Knob? {
        allCases.first { band.channel == .all && band.type == $0.type && band.freq == $0.freq && band.q == $0.q }
    }

    public func index(in preset: Preset) -> Int? { preset.bands.firstIndex { Knob.of($0) == self } }

    /// The knob's dB: its band's gain, or 0 with no band or the band off.
    public func gain(in preset: Preset) -> Double {
        guard let i = index(in: preset), preset.bands[i].on else { return 0 }
        return preset.bands[i].gain
    }

    /// The preset with the knob at gain dB: its band set, added at the end, or at 0 taken out. nil
    /// when the Q2 has no room for another band.
    public func set(_ gain: Double, in preset: Preset) -> Preset? {
        var p = preset
        let at = index(in: p)
        if gain == 0 {
            if let at { p.bands.remove(at: at) }
        } else if let at {
            p.bands[at].on = true
            p.bands[at].gain = gain
        } else if p.bands.count < EQ.maxBands {
            p.bands.append(Band(type: type, freq: freq, gain: gain, q: q))
        } else {
            return nil
        }
        return p
    }
}
