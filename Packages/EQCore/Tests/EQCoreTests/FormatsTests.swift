// SPDX-License-Identifier: GPL-3.0-only
// EQ Studio's web/formats.test.mjs and web/poweramp.test.mjs, case for case: each format read back and
// checked against the curve the Q2 plays, and Poweramp's exports as read.
import Foundation
import Testing
@testable import EQCore

private func near(_ a: Double, _ b: Double, _ within: Double, _ what: String = "", sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(a - b) <= within, "\(what) \(a) is not \(b)", sourceLocation: sourceLocation)
}
private func presetOf(_ bands: [Band], auto: Bool = true, preamp: Double = 0, balance: Double = 0) -> Preset {
    Preset(auto: auto, preamp: preamp, balance: balance, bands: bands)
}
private let shelves = [Band(type: .lowShelf, freq: 30, gain: 6, q: 0.7), Band(freq: 3000, gain: -4, q: 2), Band(type: .highShelf, freq: 9000, gain: 3, q: 0.6)]

private struct Q { let b0, b1, b2, a1, a2: Double }

/// |H| in dB at f of biquads written as miniDSP's (a1 and a2 negated).
private func biquadDb(_ list: [Q], _ f: Double, _ rate: Double) -> Double {
    let w = 2 * Double.pi * f / rate
    return list.reduce(0) { total, q in
        let (c1, s1, c2, s2) = (cos(w), sin(w), cos(2 * w), sin(2 * w))
        let num = pow(q.b0 + q.b1 * c1 + q.b2 * c2, 2) + pow(q.b1 * s1 + q.b2 * s2, 2)
        let den = pow(1 - q.a1 * c1 - q.a2 * c2, 2) + pow(q.a1 * s1 + q.a2 * s2, 2)
        return total + 10 * log10(num / den)
    }
}
private func readBiquads(_ text: String) -> [Q] {
    let r = try! Regex(#"biquad\d+,\nb0=(\S+),\nb1=(\S+),\nb2=(\S+),\na1=(\S+),\na2=(\S+?)(?:,|\n|$)"#)
    return text.matches(of: r).map { m in
        let v = (1...5).map { Double(String(m.output[$0].substring!))! }
        return Q(b0: v[0], b1: v[1], b2: v[2], a1: v[3], a2: v[4])
    }
}
/// |H| in dB at f of an impulse response, by its DFT at f.
private func impulseDb(_ s: [Double], _ f: Double, _ rate: Double) -> Double {
    var (re, im) = (0.0, 0.0)
    for n in s.indices {
        re += s[n] * cos(2 * Double.pi * f * Double(n) / rate)
        im -= s[n] * sin(2 * Double.pi * f * Double(n) / rate)
    }
    return 10 * log10(re * re + im * im)
}

@Test func waveletGetsIts127PointsLoudestAt0dB() {
    let preset = presetOf(shelves)
    let w = Formats.wavelet(preset)
    #expect(w.text.hasPrefix("GraphicEQ: 20 "))
    let points = w.text.dropFirst("GraphicEQ: ".count).trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: "; ").map { $0.split(separator: " ").map { Double($0)! } }
    #expect(points.count == 127)
    #expect(points.map { $0[0] } == Formats.waveletFreqs)
    #expect(points.map { $0[1] }.max() == 0)
    let curve = { (f: Double) in response(preset, at: f).left }
    for p in points { near(p[1] - points[0][1], curve(p[0]) - curve(20), 0.1, "\(p[0]) Hz") }
    #expect(w.notes.isEmpty)
}

@Test func waveletSaysLeftSideWhenSidesDiffer() throws {
    let w = Formats.wavelet(presetOf([Band(channel: .right, gain: 6), Band(channel: .left, freq: 100, gain: 3)], balance: 2))
    #expect(w.notes.count == 2)
    func at(_ f: Int) throws -> Double { Double(String(try #require(w.text.firstMatch(of: try Regex("[: ]\(f) (\\S+?);")))?.output[1].substring ?? ""))! }
    #expect(try at(1032) < at(103) - 2)
}

@Test func rightAloneGivesRightCurveAndFlatLeftBiquads() {
    let preset = presetOf([Band(channel: .right, freq: 1000, gain: 6)])
    let w = Formats.wavelet(preset)
    #expect(w.notes[0].contains("right side's"))
    let v = Double(String(w.text.firstMatch(of: try! Regex(#" 20 (\S+);"#))!.output[1].substring!))!
    #expect(v < -5)
    let parts = Formats.biquads(preset, rate: 48000).text.components(separatedBy: "\n\n")
    #expect(parts[0] == "Left\nNone: the left side is flat.")
    #expect(readBiquads(parts[1]).count == 1)
}

@Test func miniDSPBiquadsReadBackAsTheCurve() {
    let preset = presetOf(shelves, auto: false, preamp: -6.5)
    for rate in [48000.0, 96000] {
        let b = Formats.biquads(preset, rate: rate)
        #expect(b.text.firstMatch(of: /[eE][+-]?\d/) == nil)
        let list = readBiquads(b.text)
        #expect(list.count == 3)
        #expect(b.count == 3)
        for f in [20.0, 31, 100, 1000, 3000, 9000, 16000] { near(biquadDb(list, f, rate), response(preset, at: f, rate: rate).left, 1e-6, "\(f) Hz") }
        #expect(b.notes == ["Biquads carry no preamp: set -6.5 dB on miniDSP's gain."])
    }
}

@Test func biquadsForDifferingSidesComeAsTwoLists() {
    let preset = presetOf([Band(gain: 3), Band(channel: .left, freq: 200, gain: -2), Band(on: false, freq: 500, gain: 5), Band(freq: 700)])
    let parts = Formats.biquads(preset, rate: 48000).text.components(separatedBy: "\n\n")
    #expect(parts[0].hasPrefix("Left\n"))
    #expect(parts[1].hasPrefix("Right\n"))
    #expect(readBiquads(parts[0]).count == 2)
    #expect(readBiquads(parts[1]).count == 1)
    for f in [100.0, 200, 1000] {
        near(biquadDb(readBiquads(parts[0]), f, 48000), response(preset, at: f).left, 1e-6)
        near(biquadDb(readBiquads(parts[1]), f, 48000), response(preset, at: f).right, 1e-6)
    }
}

@Test func impulseIsTheCurveWithThePreamp() {
    let preset = presetOf(shelves)
    for rate in [44100.0, 48000] {
        let out = Formats.impulse(preset, rate: rate)
        #expect(out.count == 1)
        let preamp = autoPreamp(preset, rate: rate)
        for f in [20.0, 30, 100, 1000, 3000, 9000, 18000] {
            near(impulseDb(out[0], f, rate), response(preset, at: f, rate: rate).left + preamp, 0.01, "\(f) Hz at \(rate)")
        }
    }
}

@Test func balanceOrDifferingSidesMakeItStereo() {
    let out = Formats.impulse(presetOf([Band(freq: 1000, gain: 6)], auto: false, preamp: -6, balance: 3), rate: 48000)
    near(impulseDb(out[0], 1000, 48000), -3, 0.01)
    near(impulseDb(out[1], 1000, 48000), 0, 0.01)
    let sided = Formats.impulse(presetOf([Band(channel: .right, freq: 1000, gain: 6)], auto: false, preamp: -6), rate: 48000)
    near(impulseDb(sided[0], 1000, 48000), -6, 0.01)
    near(impulseDb(sided[1], 1000, 48000), 0, 0.01)
}

@Test func wavIs24BitPCM() {
    let d = [UInt8](Formats.wav([[1, -1, 0.5], [0, 2, -0.25]], rate: 44100))
    func u32(_ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 | Int(d[at + 2]) << 16 | Int(d[at + 3]) << 24 }
    func u16(_ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 }
    #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF")
    #expect(u32(4) == d.count - 8)
    #expect(String(decoding: d[8..<16], as: UTF8.self) == "WAVEfmt ")
    let fmt: [Int] = [u16(20), u16(22), u32(24), u16(34)]
    #expect(fmt == [1, 2, 44100, 24])
    #expect(u32(40) == 3 * 2 * 3)
    func sample(_ i: Int) -> Int { Int(d[44 + 3 * i]) | Int(d[45 + 3 * i]) << 8 | Int(Int8(bitPattern: d[46 + 3 * i])) << 16 }
    #expect((0..<6).map(sample) == [8388607, 0, -8388607, 8388607, 4194304, -2097152])
}

@Test func convolutionPastFullScaleSaysSo() {
    #expect(Formats.convolution(presetOf(shelves), rate: 48000).notes.isEmpty)
    #expect(Formats.convolution(presetOf([Band(gain: 12, q: 4)], auto: false, preamp: 0), rate: 48000).notes.count == 1)
}

// MARK: Poweramp

private func row(_ type: Int, _ f: Double, _ q: Double, _ gain: Double, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["type": type, "channels": 0, "frequency": f, "q": q, "gain": gain, "color": 0].merging(extra) { $1 }
}
private func knobs(_ bass: Double = 0, _ treble: Double = 0) -> [[String: Any]] {
    [row(0, 90, 0.800000011920929, bass), row(1, 10000, 0.6000000238418579, treble)]
}
private func json(_ v: Any) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: v), as: UTF8.self) }
private func exported(_ bands: [[String: Any]], _ extra: [String: Any] = [:]) -> String {
    json([["name": "Export", "preamp": -6.049314498901367, "parametric": true, "bands": bands].merging(extra) { $1 }])
}
private func pread(_ text: String, _ name: String = "") throws -> Poweramp.Read { try Poweramp.read(text, name: name).get() }
private func shape(_ p: Preset) -> [String] { normalize(p).bands.map { "\($0.type.rawValue) \($0.freq) \($0.gain) \($0.q)" } }

@Test func anExportReadsWithItsKnobsAsShelves() throws {
    let r = try pread(exported(knobs(7.486961841583252, 7.455280780792236) + [
        row(4, 105, 0.699999988079071, 7.5, ["color": -7859968]), row(3, 181, 0.18000000715255737, -5.999999523162842),
        row(2, 897, 1.5, 11.399999618530273), row(5, 6667, 0.699999988079071, 9.0),
    ]))
    #expect(r.preset.name == "Export")
    #expect(r.preset.auto == false)
    #expect(normalize(r.preset).preamp == -6.05)
    #expect(shape(r.preset) == ["LSC 90.0 7.49 0.8", "HSC 10000.0 7.46 0.6", "LSC 105.0 7.5 0.7", "PK 181.0 -6.0 0.18", "PK 897.0 11.4 1.5", "HSC 6667.0 9.0 0.7"])
    #expect(Knob.bass.gain(in: normalize(r.preset)) == 7.49)
    #expect(Knob.treble.gain(in: normalize(r.preset)) == 7.46)
    #expect(r.notes == ["The band at 897 Hz is of a kind Poweramp's file doesn't name. It's read as a peak, and may not sound quite as in Poweramp."])
}

@Test func unturnedKnobsMakeNoBand() throws {
    let r = try pread(exported(knobs() + [row(2, 29, 5.71221923828125, -2.6101746559143066), row(2, 47, 9.995567321777344, 11.959613800048828)]))
    #expect(shape(r.preset) == ["PK 29.0 -2.61 5.712", "PK 47.0 11.96 9.996"])
    #expect(try parse(serialize(r.preset)).get().bands == normalize(r.preset).bands)
    let many = try pread(exported(knobs() + [29.0, 38, 47, 55].map { row(2, $0, 5, 3) }))
    #expect(many.notes[0].hasPrefix("4 bands are of a kind"))
}

@Test func whatTheQ2LacksIsLeftOutOrBroughtIn() throws {
    let r = try pread(json([
        ["name": "One", "preamp": 0, "parametric": true, "bands": knobs(3) + [row(3, 250, 12, 2), row(3, 2000, 1, 3, ["channels": 1]), row(9, 500, 1, 1), row(3, 24000, 1, 1)]],
        ["name": "Two", "preamp": 0, "parametric": true, "bands": [Any]()],
    ]))
    #expect(shape(r.preset) == ["LSC 90.0 3.0 0.8", "PK 250.0 2.0 10.0", "PK 20000.0 1.0 1.0"])
    #expect(r.notes == [
        "The file holds 2 presets. This is the first.",
        "The band at 2000 Hz is for one side only, and the file doesn't say which, so it's left out.",
        "A band couldn't be read, so it's left out.",
        "The bands at 250 Hz and 24000 Hz go past what the Q2 takes, 20 Hz to 20 kHz and Q 0.1 to 10, so they're brought inside it.",
    ])
    let many = try pread(exported((0..<32).map { row(3, 100 + Double($0), 1, 1) }))
    #expect(many.notes.joined(separator: " ").contains("the last 2 are left out"))
    #expect(normalize(many.preset).bands.count == EQ.maxBands)
}

@Test func aNameComesFromTheFileElseItsFileName() throws {
    #expect(try pread(exported([]), "file").preset.name == "Export")
    #expect(try pread(exported([], ["name": " "]), "file").preset.name == "file")
    #expect(try pread(json(["preamp": 1, "bands": [Any]()]), "file").preset.name == "file")
}

@Test func whatIsNotAParametricExportIsRefused() {
    if case .failure(let e) = Poweramp.read(exported(knobs(), ["parametric": false])) { #expect(e.reason.contains("graphic EQ")) } else { Issue.record("read") }
    for t in ["[", "[]", #"{"bands": 3}"#, #""x""#, "null"] {
        if case .success = Poweramp.read(t) { Issue.record("\(t) read") }
    }
}

@Test func jsonIsToldByItsFirstCharacter() {
    #expect(Poweramp.isJSON("\u{FEFF} \n[{\"bands\": []}]"))
    #expect(Poweramp.isJSON("{}"))
    #expect(!Poweramp.isJSON("Preamp: -3 dB\n"))
    #expect(!Poweramp.isJSON("# [comment]\n"))
}
