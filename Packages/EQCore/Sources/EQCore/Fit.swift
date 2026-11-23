// SPDX-License-Identifier: GPL-3.0-only
// An EQ worked out from a measurement and a target, as EQ Studio's web/fit.js: the Q2's bands that bring
// the one to the other. AutoEq's shape: a low shelf at 105 Hz and a high shelf at 10 kHz, Q 0.7, and peaks
// between, each placed where the curve is furthest off, then every band moved in turn until none brings it
// closer. Nothing past 10 kHz is chased, where each ear and each fit differ, treble cuts stop at 6 dB, as a
// coupler's own resonance shows there, and boosts stop at maxBoost.
import Foundation

public enum Fit {
    static let rate = 48000.0
    static let low = 20.0, high = 20000.0
    public static let reach = 10000.0 // past this the fit wants no change
    static let peakTop = 9000.0 // the highest a peak goes
    static let perOctave = 48.0
    public static let freqs: [Double] = {
        var out: [Double] = []
        var f = low
        while f <= high { out.append(f); f *= pow(2, 1 / perOctave) }
        return out
    }()
    static let shelfQ = 0.7
    static let qRange = (0.4, 6.0)
    static let gainRange = (-12.0, 12.0)
    static let gainCost = 0.1 // a little for each band's gain, so two bands don't fight to undo each other
    /// How much each point counts: the treble less, its measurement the least sure; past the reach a
    /// little, so the high shelf can't swing the top octave about.
    static let weights: [Double] = freqs.map { $0 > reach ? 0.3 : $0 > 6000 || $0 < 30 ? 0.5 : 1 }

    static func clamp(_ v: Double, _ r: (Double, Double)) -> Double { min(max(v, r.0), r.1) }

    /// A curve as text: a frequency and a level a line, as REW, a graph tool or AutoEq write it.
    public static func readCurve(_ text: String) -> [(Double, Double)] { Squig.readCurve(text) }

    /// A curve at freqs, straight between its points on a log scale, flat past its ends.
    static func onGrid(_ points: [(Double, Double)]) -> [Double] {
        var out = [Double](repeating: 0, count: freqs.count)
        var j = 0
        for (i, f) in freqs.enumerated() {
            while j < points.count - 2 && points[j + 1].0 < f { j += 1 }
            let ((f0, a), (f1, b)) = (points[j], points[j + 1])
            let t = clamp(log(f / f0) / log(f1 / f0), (0, 1))
            out[i] = a + (b - a) * t
        }
        return out
    }

    /// A moving average a fraction of an octave wide, wider up the treble: the trend, not each resonance.
    static func smooth(_ values: [Double]) -> [Double] {
        var sums = [0.0]
        for v in values { sums.append(sums.last! + v) }
        return freqs.enumerated().map { i, f in
            let half = max(1, Int((perOctave * (f < 2000 ? 1.0 / 12 : f < 6000 ? 1.0 / 6 : 1.0 / 2) / 2).rounded(.toNearestOrAwayFromZero)))
            let (a, b) = (max(0, i - half), min(values.count, i + half + 1))
            return (sums[b] - sums[a]) / Double(b - a)
        }
    }

    static func bandCurve(_ band: Band) -> [Double] {
        var b = band
        b.on = true
        b.channel = .all
        guard let filter = design(b, rate: rate) else { return [Double](repeating: 0, count: freqs.count) }
        return freqs.map { 10 * log10(power(filter, at: $0, rate: rate)) }
    }

    static func cost(_ goal: [Double], _ curves: [[Double]], _ bands: [Band]) -> Double {
        var sum = gainCost * bands.reduce(0) { $0 + $1.gain * $1.gain }
        for i in freqs.indices {
            var level = 0.0
            for c in curves { level += c[i] }
            let d = goal[i] - level
            sum += weights[i] * d * d
        }
        return sum
    }

    enum Field: CaseIterable { case freq, gain, q }
    static let smallest: [Field: Double] = [.freq: 0.005, .q: 0.005, .gain: 0.02]

    /// Every band's values nudged in turn, a step up or down, kept when the curve comes closer, the step
    /// halved when neither does, until no step is left worth taking.
    static func settle(_ goal: [Double], _ bands: inout [Band], rounds: Int) {
        var curves = bands.map(bandCurve)
        var best = cost(goal, curves, bands)
        // A peak's fields in the page's order (freq, gain, q); a shelf's gain alone.
        var steps: [[(Field, Double)]] = bands.map { $0.type == .peak ? [(.freq, 1.0 / 6), (.gain, 1), (.q, 0.25)] : [(.gain, 1)] }
        for _ in 0..<rounds {
            var live = false
            for index in bands.indices {
                for (k, (field, step)) in steps[index].enumerated() {
                    if step < smallest[field]! { continue }
                    live = true
                    var better = false
                    for dir in [1.0, -1.0] {
                        var next = bands[index]
                        switch field {
                        case .freq: next.freq = clamp(next.freq * pow(2, dir * step), (low, peakTop))
                        case .q: next.q = clamp(next.q * pow(2, dir * step), qRange)
                        case .gain: next.gain = clamp(next.gain + dir * step, gainRange)
                        }
                        let old = curves[index]
                        curves[index] = bandCurve(next)
                        var trial = bands
                        trial[index] = next
                        let now = cost(goal, curves, trial)
                        if now < best - 1e-9 {
                            best = now
                            bands[index] = next
                            better = true
                            break
                        }
                        curves[index] = old
                    }
                    if !better { steps[index][k].1 = step / 2 }
                }
            }
            if !live { break }
        }
    }

    static func sign(_ v: Double) -> Double { v > 0 ? 1 : v < 0 ? -1 : 0 }

    /// Where the curve is furthest off, under the peaks' top: a peak there, as wide as the bump at half its height.
    static func nextPeak(_ goal: [Double], _ bands: [Band]) -> Band {
        let curves = bands.map(bandCurve)
        let off = freqs.indices.map { i in goal[i] - curves.reduce(0) { $0 + $1[i] } }
        var at = 0
        var i = 0
        while i < freqs.count && freqs[i] <= peakTop {
            if abs(off[i]) * weights[i] > abs(off[at]) * weights[at] { at = i }
            i += 1
        }
        let height = off[at]
        let inside = { (i: Int) in i >= 0 && i < freqs.count && sign(off[i]) == sign(height) && abs(off[i]) > abs(height) / 2 }
        var (a, b) = (at, at)
        while inside(a - 1) { a -= 1 }
        while inside(b + 1) { b += 1 }
        let octaves = max(Double(b - a + 1) / perOctave, 1.0 / 6)
        let q = pow(2, octaves).squareRoot() / (pow(2, octaves) - 1)
        return Band(type: .peak, freq: freqs[at], gain: clamp(height, gainRange), q: clamp(q, qRange))
    }

    public struct Result: Sendable {
        public let bands: [Band]
        public let goal: [Double]
        public let rms: Double
    }

    public struct NoCurve: Error, LocalizedError, Sendable {
        public let errorDescription: String?
    }

    /// The Q2's bands for a measurement (a side each) and a target, the goal they were fitted to at freqs,
    /// and how far from it they leave the curve, an RMS in dB.
    public static func fit(measurement: [[(Double, Double)]], target: [(Double, Double)], bands count: Int = 10,
                           maxBoost: Double = 6) throws -> Result {
        let sides = measurement.filter { $0.count >= 2 }.map(onGrid)
        if sides.isEmpty { throw NoCurve(errorDescription: "There is no measurement to fit.") }
        if target.count < 2 { throw NoCurve(errorDescription: "There is no target to fit to.") }
        let wanted = onGrid(target)
        let heard = freqs.indices.map { i in sides.reduce(0) { $0 + $1[i] } / Double(sides.count) }
        let raw = smooth(freqs.indices.map { wanted[$0] - heard[$0] })
        // 0 dB at 500 Hz, where the graph lines a target and a measurement up.
        let centre = raw[freqs.firstIndex { $0 >= 500 }!]
        let goal = raw.enumerated().map { i, v in
            freqs[i] > reach ? 0 : clamp(v - centre, (freqs[i] > 6000 ? -6 : gainRange.0, maxBoost))
        }

        var bands = [Band(type: .lowShelf, freq: 105, gain: 0, q: shelfQ), Band(type: .highShelf, freq: 10000, gain: 0, q: shelfQ)]
        settle(goal, &bands, rounds: 20)
        while bands.count < count {
            bands.append(nextPeak(goal, bands))
            settle(goal, &bands, rounds: 12)
        }
        settle(goal, &bands, rounds: 200)
        let out = bands.map { b in
            Band(type: b.type, freq: (b.freq + 0.5).rounded(.down), gain: (b.gain * 10 + 0.5).rounded(.down) / 10,
                 q: (b.q * 100 + 0.5).rounded(.down) / 100)
        }.filter { abs($0.gain) >= 0.1 }
        return Result(bands: out, goal: goal, rms: rms(goal, out))
    }

    /// How far bands leave the curve from a goal at freqs: RMS dB up to the reach, an offset aside.
    public static func rms(_ goal: [Double], _ bands: [Band]) -> Double {
        let curves = bands.map(bandCurve)
        var off: [Double] = []
        var i = 0
        while i < freqs.count && freqs[i] <= reach {
            off.append(goal[i] - curves.reduce(0) { $0 + $1[i] })
            i += 1
        }
        let mean = off.reduce(0, +) / Double(off.count)
        return (off.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(off.count)).squareRoot()
    }
}
