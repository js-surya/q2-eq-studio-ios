// SPDX-License-Identifier: GPL-3.0-only
// The curve: peq_compile's filters, their response, Auto's preamp and the warnings, as web/eq.js.
import Foundation

private let tau = 6.283185307179586
private let grid = 1024 // peak()'s points
private let noPeak = 1.0000230261 // under 0.0001 dB is none
private let clipSlack = 0.1 // dB: AutoEQ's preamps are rounded to this, so a peak this far over is no news

public struct Biquad: Sendable {
    public let b0, b1, b2, a1, a2: Double
    public let channel: Channel
}

/// peq_compile's filter for a band at this rate, or nil where the Q2 skips it.
public func design(_ band: Band, rate: Double) -> Biquad? {
    if !band.on || band.gain == 0 || band.freq >= rate * 0.5 { return nil }
    let a = pow(10, band.gain / 40)
    let w = tau * band.freq / rate
    let c = cos(w)
    let alpha = sin(w) / (2 * band.q)
    let r = 2 * a.squareRoot() * alpha
    let b0, b1, b2, a0, a1, a2: Double
    switch band.type {
    case .peak:
        (b0, b1, b2) = (1 + alpha * a, -2 * c, 1 - alpha * a)
        (a0, a1, a2) = (1 + alpha / a, -2 * c, 1 - alpha / a)
    case .lowShelf:
        b0 = a * ((a + 1) - (a - 1) * c + r); b1 = 2 * a * ((a - 1) - (a + 1) * c)
        b2 = a * ((a + 1) - (a - 1) * c - r); a0 = (a + 1) + (a - 1) * c + r
        a1 = -2 * ((a - 1) + (a + 1) * c); a2 = (a + 1) + (a - 1) * c - r
    case .highShelf:
        b0 = a * ((a + 1) + (a - 1) * c + r); b1 = -2 * a * ((a - 1) + (a + 1) * c)
        b2 = a * ((a + 1) + (a - 1) * c - r); a0 = (a + 1) - (a - 1) * c + r
        a1 = 2 * ((a - 1) - (a + 1) * c); a2 = (a + 1) - (a - 1) * c - r
    }
    return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0, channel: band.channel)
}

func designAll(_ preset: Preset, rate: Double) -> [Biquad] { preset.bands.compactMap { design($0, rate: rate) } }

/// |H|^2 of a band's filter at f.
func power(_ f: Biquad, at freq: Double, rate: Double) -> Double {
    let w = tau * freq / rate
    let (c1, s1) = (cos(w), sin(w))
    let (c2, s2) = (2 * c1 * c1 - 1, 2 * s1 * c1)
    let nr = f.b0 + f.b1 * c1 + f.b2 * c2
    let ni = f.b1 * s1 + f.b2 * s2
    let dr = 1 + f.a1 * c1 + f.a2 * c2
    let di = f.a1 * s1 + f.a2 * s2
    return (nr * nr + ni * ni) / (dr * dr + di * di)
}

/// peq_response: |H|^2 of each channel's chain, without preamp or balance.
func chain(_ filters: [Biquad], at f: Double, rate: Double) -> (left: Double, right: Double) {
    var (left, right) = (1.0, 1.0)
    for filter in filters {
        let m = power(filter, at: f, rate: rate)
        if filter.channel != .right { left *= m }
        if filter.channel != .left { right *= m }
    }
    return (left, right)
}

private func db(_ ratio: Double) -> Double { 10 * log10(ratio) }

/// Each channel's gain in dB at f.
public func response(_ preset: Preset, at f: Double, rate: Double = EQ.autoRate) -> (left: Double, right: Double) {
    let (l, r) = chain(designAll(preset, rate: rate), at: f, rate: rate)
    return (db(l), db(r))
}

/// The curve at many points at once, the filters designed once.
public func responses(_ preset: Preset, at freqs: [Double], rate: Double = EQ.autoRate) -> [(left: Double, right: Double)] {
    let filters = designAll(preset, rate: rate)
    return freqs.map { f in
        let (l, r) = chain(filters, at: f, rate: rate)
        return (db(l), db(r))
    }
}

/// One band's own gain in dB at f, for showing it alone.
public func bandResponse(_ band: Band, at f: Double, rate: Double = EQ.autoRate) -> Double {
    guard let filter = design(band, rate: rate) else { return 0 }
    return db(power(filter, at: f, rate: rate))
}

/// peak(): the loudest |H|^2 of either channel on the Q2's own points, and where. At least 1, as
/// Auto never boosts, and at most 60 dB. The Q2 counts down to DC, where a low shelf's boost sits.
/// low leaves out what is under it, for saying what music can reach.
public func peak(_ preset: Preset, rate: Double, low: Double = 0) -> (power: Double, at: Double) {
    let filters = designAll(preset, rate: rate)
    let nyquist = rate * 0.5
    var points: [Double] = [0, nyquist]
    for k in 0..<grid { points.append(pow(nyquist, Double(k) / Double(grid - 1))) }
    points += preset.bands.map(\.freq)
    if low != 0 { points.append(low) }
    var (best, at) = (1.0, low)
    for (index, f) in points.enumerated() {
        if (f >= nyquist && index != 1) || f < low { continue }
        let (l, r) = chain(filters, at: f, rate: rate)
        let loudest = max(l, r)
        if loudest > best { (best, at) = (loudest, f) }
    }
    return (best < noPeak ? 1 : min(best, 1e6), at)
}

/// peq_auto: the cut in dB that keeps that peak under full scale.
public func autoPreamp(_ preset: Preset, rate: Double = EQ.autoRate) -> Double {
    let loudest = peak(preset, rate: rate).power
    return loudest > 1 ? -db(loudest) : 0
}

/// Worth a second look, never a reason to refuse saving.
public func warnings(_ preset: Preset, rate: Double = EQ.autoRate) -> [String] {
    let clean = normalize(preset)
    var out: [String] = []
    if !clean.bands.contains(where: { $0.on && $0.gain != 0 }) { out.append("No band changes the sound yet.") }
    let loudest = peak(clean, rate: rate, low: EQ.freqMin).power
    let over = db(loudest) + clean.preamp
    if !clean.auto && over > clipSlack {
        out.append("Peaks reach \(decimal(over, 1)) dB over full scale, so loud music may clip. Lower the preamp, or use Auto.")
    }
    if clean.auto && clean.balance != 0 {
        out.append("Balance needs a fixed preamp in the file, so this saves Auto as \(decimal(autoPreamp(clean), 1)) dB.")
    }
    return out
}
