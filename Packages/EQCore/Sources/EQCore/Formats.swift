// SPDX-License-Identifier: GPL-3.0-only
// A preset for other apps, as EQ Studio's web/formats.js: Wavelet's GraphicEQ, miniDSP's biquads, and an
// impulse response as a .wav for a convolver (Equalizer APO's, Roon's, JamesDSP's). Each is the curve the
// Q2 plays, its filters as design() makes them; what a format can't hold is said in notes.
import Foundation

public enum Formats {
    /// The 127 points Wavelet's GraphicEQ takes, as AutoEq writes them.
    public static let waveletFreqs: [Double] = [
        20, 21, 22, 23, 24, 26, 27, 29, 30, 32, 34, 36, 38, 40, 43, 45, 48, 50, 53, 56, 59, 63, 66, 70, 74, 78, 83,
        87, 92, 97, 103, 109, 115, 121, 128, 136, 143, 151, 160, 169, 178, 188, 199, 210, 222, 235, 248, 262, 277,
        292, 309, 326, 345, 364, 385, 406, 429, 453, 479, 506, 534, 565, 596, 630, 665, 703, 743, 784, 829, 875, 924,
        977, 1032, 1090, 1151, 1216, 1284, 1357, 1433, 1514, 1599, 1689, 1784, 1885, 1991, 2103, 2221, 2347, 2479,
        2618, 2766, 2921, 3086, 3260, 3443, 3637, 3842, 4058, 4287, 4528, 4783, 5052, 5337, 5637, 5955, 6290, 6644,
        7018, 7414, 7831, 8272, 8738, 9230, 9749, 10298, 10878, 11490, 12137, 12821, 13543, 14305, 15110, 15961,
        16860, 17809, 18812, 19871,
    ]
    static let waveletRate = 48000.0
    public static let impulseLength = 65536 // a Q 10 peak at 20 Hz has rung down past -100 dB by then, at 48 kHz
    static let pcmMax = 8388607.0 // 24-bit

    public struct Text: Sendable { public let text: String; public let notes: [String]; public var count = 0 }
    public struct Wav: Sendable { public let data: Data; public let notes: [String] }

    /// JS's (Math.round(v * 10) / 10 || 0).toFixed(1): halves up, no -0.
    static func tenth(_ v: Double) -> String {
        var r = (v * 10 + 0.5).rounded(.down) / 10
        if r == 0 { r = 0 }
        return String(format: "%.1f", r)
    }

    static func db(_ v: Double) -> String { (v > 0 ? "+" : "") + tenth(v) }

    enum Side { case all, left, right }

    /// The filters each side plays: one list when both sides are the same, else the left's and the right's.
    static func sides(_ preset: Preset, rate: Double) -> [(side: Side, filters: [Biquad])] {
        let filters = preset.bands.compactMap { design($0, rate: rate) }
        if filters.allSatisfy({ $0.channel == .all }) { return [(.all, filters)] }
        return [(.left, filters.filter { $0.channel != .right }), (.right, filters.filter { $0.channel != .left })]
    }

    /// The preamp the Q2 plays at this rate: Auto's figure, or the one set.
    static func preampAt(_ preset: Preset, rate: Double) -> Double { preset.auto ? autoPreamp(preset, rate: rate) : preset.preamp }

    /// Wavelet's GraphicEQ line. Wavelet has one curve for both sides, and its own preamp and balance, so
    /// the curve's loudest point is 0 dB, as AutoEq writes it.
    public static func wavelet(_ input: Preset) -> Text {
        let preset = normalize(input)
        let lists = sides(preset, rate: waveletRate)
        let right = lists.count > 1 && lists[0].filters.isEmpty // bands on the right alone: the right's curve
        var notes: [String] = []
        if lists.count > 1 { notes.append("Wavelet's EQ is the same on both sides, so this is the \(right ? "right" : "left") side's.") }
        if preset.balance != 0 { notes.append("Wavelet has its own balance, so this one isn't in it.") }
        let gains = responses(preset, at: waveletFreqs, rate: waveletRate).map { right ? $0.right : $0.left }
        let top = gains.max() ?? 0
        let points = zip(waveletFreqs, gains).map { "\(Int($0)) \(tenth($1 - top))" }
        return Text(text: "GraphicEQ: \(points.joined(separator: "; "))\n", notes: notes)
    }

    /// A coefficient as miniDSP's text has them: a plain decimal, never an exponent.
    static func coefficient(_ v: Double) -> String {
        let text = String(format: "%.15f", v)
        return text.hasPrefix("-") && text.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) ? String(text.dropFirst()) : text
    }

    /// miniDSP's biquads at rate, a1 and a2 negated as miniDSP takes them. Sides that differ come as two
    /// lists, each headed, to paste into each output's own; the preamp and balance go in miniDSP's gain.
    public static func biquads(_ input: Preset, rate: Double) -> Text {
        let preset = normalize(input)
        let lists = sides(preset, rate: rate)
        var notes: [String] = []
        let preamp = preampAt(preset, rate: rate)
        if preamp != 0 { notes.append("Biquads carry no preamp: set \(db(preamp)) dB on miniDSP's gain.") }
        if preset.balance != 0 {
            notes.append("Turn the \(preset.balance > 0 ? "left" : "right") side down \(String(format: "%.1f", abs(preset.balance))) dB more there for the balance.")
        }
        let blocks = lists.map { side, filters -> String in
            let text = filters.enumerated().map { i, f in
                "biquad\(i + 1),\nb0=\(coefficient(f.b0)),\nb1=\(coefficient(f.b1)),\nb2=\(coefficient(f.b2)),\n"
                    + "a1=\(coefficient(-f.a1)),\na2=\(coefficient(-f.a2))"
            }.joined(separator: ",\n")
            let name = side == .left ? "Left" : "Right"
            return side == .all ? text : "\(name)\n\(text.isEmpty ? "None: the \(name.lowercased()) side is flat." : text)"
        }
        let count = lists.map(\.filters.count).max() ?? 0
        if count > 10 { notes.append("\(count) biquads an output: more than the 10 many miniDSPs take, as the 2x4 HD.") }
        return Text(text: blocks.joined(separator: "\n\n") + "\n", notes: notes, count: count)
    }

    /// Each side's impulse response at rate: the filters run on an impulse, with the preamp and balance in
    /// it. One channel when both sides are the same.
    public static func impulse(_ input: Preset, rate: Double, length: Int = impulseLength) -> [[Double]] {
        let preset = normalize(input)
        var lists = sides(preset, rate: rate)
        if preset.balance != 0 && lists.count == 1 { lists.append(lists[0]) }
        let preamp = preampAt(preset, rate: rate)
        return lists.enumerated().map { index, entry in
            let side = lists.count == 1 ? 0 : index > 0 ? min(preset.balance, 0) : min(-preset.balance, 0)
            var out = [Double](repeating: 0, count: length)
            var state = [(Double, Double)](repeating: (0, 0), count: entry.filters.count)
            out[0] = pow(10, (preamp + side) / 20)
            for n in 0..<length {
                var x = out[n]
                for (k, f) in entry.filters.enumerated() { // direct form II transposed
                    let y = f.b0 * x + state[k].0
                    state[k] = (f.b1 * x - f.a1 * y + state[k].1, f.b2 * x - f.a2 * y)
                    x = y
                }
                out[n] = x
            }
            return out
        }
    }

    /// 24-bit PCM .wav of channels at rate; a sample past full scale is held at it.
    public static func wav(_ channels: [[Double]], rate: Int) -> Data {
        let count = channels.count, length = channels[0].count
        let size = length * count * 3
        var d = Data(capacity: 44 + size)
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + size)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(count); u32(rate); u32(rate * count * 3); u16(count * 3); u16(24)
        d.append(contentsOf: Array("data".utf8)); u32(size)
        var bytes = [UInt8](repeating: 0, count: size)
        var at = 0
        for n in 0..<length {
            for channel in channels {
                let sample = Int32((min(max(channel[n], -1), 1) * pcmMax).rounded(.toNearestOrAwayFromZero))
                bytes[at] = UInt8(truncatingIfNeeded: sample)
                bytes[at + 1] = UInt8(truncatingIfNeeded: sample >> 8)
                bytes[at + 2] = UInt8(truncatingIfNeeded: sample >> 16)
                at += 3
            }
        }
        d.append(contentsOf: bytes)
        return d
    }

    /// The .wav a convolver loads, and what to know about it.
    public static func convolution(_ input: Preset, rate: Double) -> Wav {
        let preset = normalize(input)
        let channels = impulse(preset, rate: rate)
        var notes: [String] = []
        if channels.count == 2 { notes.append("Stereo: the sides differ.") }
        if channels.contains(where: { $0.contains { abs($0) > 1 } }) {
            notes.append("The preamp leaves it past full scale, so it clips: lower the preamp, or use Auto.")
        }
        return Wav(data: wav(channels, rate: Int(rate)), notes: notes)
    }
}
