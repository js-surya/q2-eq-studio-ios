// SPDX-License-Identifier: GPL-3.0-only
// EQ Studio's web/eq.test.mjs, case for case: the cases a person can check by hand. The page's own
// tests run its logic and the firmware's patch/peq.c on the same files; these hold the port to it.
import Foundation
import Testing
@testable import EQCore

private func near(_ a: Double, _ b: Double, _ within: Double = 1e-9, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(a - b) <= within, "\(a) is not \(b)", sourceLocation: sourceLocation)
}

private func read(_ text: String) throws -> Preset { try parse(text).get() }
private func error(_ text: String) -> String? {
    if case .failure(let e) = parse(text) { return e.message }
    return nil
}
private func presetOf(_ bands: [Band], auto: Bool = true, preamp: Double = 0, balance: Double = 0) -> Preset {
    Preset(name: "", auto: auto, preamp: preamp, balance: balance, bands: bands)
}

private func catalogue() throws -> Catalogue {
    let url = try #require(Bundle.module.url(forResource: "presets.json", withExtension: "gz"))
    let gz = try Data(contentsOf: url)
    // gunzip with the system's tool: the app gets it unzipped from URLSession.
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gz")
    try gz.write(to: tmp)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
    p.arguments = ["-c", tmp.path]
    let pipe = Pipe()
    p.standardOutput = pipe
    try p.run()
    let json = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return try Catalogue(json: json)
}

@Test func everyBuiltInPresetIsAFileTheQ2CanImport() throws {
    let c = try catalogue()
    #expect(c.credit.contains("AutoEq"))
    #expect(c.presets.count > 8000)
    let legal = try Regex(#"^[^.\\/:*?"<>|][^\\/:*?"<>|]*[^. ]\.txt$"#)
    for entry in c.presets {
        let preset = try read(entry.text)
        #expect(preset.auto == false, "\(entry.name)")
        #expect(!preset.bands.isEmpty && preset.bands.count <= EQ.maxBands, "\(entry.name)")
        #expect(try read(serialize(normalize(preset))) == normalize(preset), "\(entry.name), \(entry.source)")
        #expect(fileName(entry.name).wholeMatch(of: legal) != nil, "\(entry.name)")
    }
}

@Test func theShortListIs25CleanNamesThatFitTheirPreamps() throws {
    let top = try catalogue().top
    #expect(top.count == 25)
    #expect(Set(top.map(\.name)).count == 25)
    for entry in top {
        #expect(fileName(entry.name) == "\(entry.name).txt")
        #expect(warnings(try read(entry.text)) == [], "\(entry.name)")
    }
}

@Test func aNewPresetIsTheQ2Reset() {
    let p = Preset.flat()
    #expect(p.bands.map(\.freq) == [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
    #expect(p.bands.allSatisfy { $0.gain == 0 && $0.q == 1.41 && $0.type == .peak })
    #expect(autoPreamp(p) == 0)
}

@Test func aTypicalAutoEQFileReadsAsWritten() throws {
    let p = try read(["Preamp: -6.4 dB", "Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70",
                      "Filter 2: ON PK Fc 3200 Hz Gain -2.1 dB Q 1.41", "Filter 3: OFF HSC Fc 10000 Hz Gain 3 dB Q 0.7", ""]
        .joined(separator: "\r\n"))
    #expect(p.auto == false)
    #expect(p.preamp == -6.4)
    #expect(p.bands == [Band(type: .lowShelf, freq: 105, gain: 5.5, q: 0.7), Band(freq: 3200, gain: -2.1, q: 1.41),
                        Band(on: false, type: .highShelf, freq: 10000, gain: 3, q: 0.7)])
}

@Test func noPreampLineMeansAuto() throws {
    #expect(try read("Filter: ON PK Fc 1000 Hz Gain 3 dB Q 1\n").auto)
}

@Test func channelSectionsAndSidePreampsBecomeBandsAndBalance() throws {
    let p = try read("Channel: L\nPreamp: -2 dB\nFilter 1: ON PK Fc 100 Hz Gain 1 dB Q 1\n"
        + "Channel: R\nPreamp: -5 dB\nFilter 2: ON PK Fc 200 Hz Gain 1 dB Q 1\nChannel: all\nFilter 3: ON PK Fc 300 Hz Gain 1 dB Q 1\n")
    #expect(p.bands.map(\.channel) == [.left, .right, .all])
    #expect(p.preamp == -2)
    #expect(p.balance == -3)
}

@Test func theSameWordsRefuseWhatTheQ2Refuses() {
    let refused = [
        ("Filter 1: ON BP Fc 100 Hz Gain 1 dB Q 1", "Line 1: unsupported filter type"),
        ("Filter 1: ON PK Fc 100 Hz Gain 1 dB", "Line 1: peaking filter requires Q"),
        ("Filter 1: ON PK Fc 10 Hz Gain 1 dB Q 1", "Line 1: range: 20..20000 Hz, -24..24 dB, Q 0.1..10"),
        ("\nInclude: other.txt", "Line 2: unsupported command"),
        ("Preamp: 30 dB", "Line 1: preamp outside -60..24 dB or invalid number"),
        ("Channel: X", "Line 1: only channels L, R and all are supported"),
    ]
    for (text, message) in refused { #expect(error(text) == message) }
    #expect(error(String(repeating: "#", count: 16385)) == "Line 1: file exceeds 16384 bytes")
    #expect(error(String(repeating: "#", count: 513)) == "Line 1: line exceeds 512 bytes")
    let many = (1...31).map { "Filter \($0): ON PK Fc 100 Hz Gain 1 dB Q 1" }.joined(separator: "\n")
    #expect(error(many) == "Line 31: more than 30 bands")
}

@Test func blankSlotsAreSkipped() throws {
    #expect(try read("Filter 1: OFF PK Fc 0 Hz Gain 0 dB Q 0\nFilter 2: ON None\n").bands.isEmpty)
}

@Test func anExponentWithNoDigitsReadsAsTheQ2ReadsIt() throws {
    #expect(try read("Filter: ON PK Fc 355E Hz Gain 1e+ dB Q 1.5e\n").bands[0].freq == 355)
    #expect(error("Filter: ON PK Fc .e5 Hz Gain 1 dB Q 1\n") == "Line 1: invalid frequency or gain number")
}

@Test func aCommaIsADecimalMarkAndHashEndsALine() throws {
    let b = try read("Filter 1: ON PK Fc 1000,5 Hz Gain 2,5 dB Q 1 # note\n").bands[0]
    #expect(b.freq == 1000.5)
    #expect(b.gain == 2.5)
}

@Test func lsAndHsWithAQMoveToTheCentre() throws {
    near(try read("Filter: ON LSC Fc 100 Hz Gain 6 dB Q 0.7\n").bands[0].freq, 100)
    #expect(try read("Filter: ON LS Fc 100 Hz Gain 6 dB Q 0.7\n").bands[0].freq != 100)
}

@Test func whatIsWrittenReadsBackTheSame() throws {
    let p = normalize(presetOf([
        Band(type: .lowShelf, freq: 105, gain: 5.5, q: 0.7), Band(channel: .left, freq: 3200, gain: -2.1, q: 1.41),
        Band(channel: .right, freq: 4000, gain: 1, q: 3), Band(on: false, freq: 9000, gain: 2, q: 2),
    ], auto: false, preamp: -6.4))
    #expect(try read(serialize(p)) == p)
    #expect(serialize(p) == ["Preamp: -6.4 dB", "Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.7", "Channel: L",
                             "Filter 2: ON PK Fc 3200 Hz Gain -2.1 dB Q 1.41", "Channel: R",
                             "Filter 3: ON PK Fc 4000 Hz Gain 1 dB Q 3", "Channel: all",
                             "Filter 4: OFF PK Fc 9000 Hz Gain 2 dB Q 2", ""].joined(separator: "\n"))
}

@Test func balanceIsWrittenAsTheTwoSidePreamps() throws {
    for balance in [3.5, -7] {
        let p = normalize(presetOf([Band(gain: 2)], auto: false, preamp: -1, balance: balance))
        #expect(try read(serialize(p)) == p)
    }
}

@Test func autoWithBalanceSavesIts48kHzCut() throws {
    let p = presetOf([Band(gain: 6, q: 1)], balance: 2)
    let parsed = try read(serialize(p))
    #expect(parsed.auto == false)
    near(parsed.preamp, -6, 0.01)
    #expect(parsed.balance == 2)
    #expect(warnings(p).joined(separator: " ").contains("saves Auto as -6 dB"))
}

@Test func aPeakFilterGivesItsGainAtItsCentre() {
    for gain in [6.0, -9, 24] { near(response(presetOf([Band(gain: gain, q: 2)]), at: 1000).left, gain) }
}

@Test func shelvesReachTheirGainOnTheirOwnSide() {
    let low = presetOf([Band(type: .lowShelf, freq: 200, gain: 6, q: 0.7)])
    near(response(low, at: 20).left, 6, 0.01)
    near(response(low, at: 20000).left, 0, 0.01)
    near(response(low, at: 200).left, 3, 0.01)
    let high = presetOf([Band(type: .highShelf, freq: 2000, gain: -6, q: 0.7)])
    near(response(high, at: 20).left, 0, 0.01)
    near(response(high, at: 15000).left, -6, 0.05)
}

@Test func aSideBandChangesOnlyThatSide() {
    let r = response(presetOf([Band(channel: .right, gain: 6, q: 1)]), at: 1000)
    near(r.left, 0)
    near(r.right, 6)
}

@Test func offZeroAndPastNyquistBandsDoNothing() {
    for b in [Band(on: false, gain: 6), Band(gain: 0), Band(freq: 20000, gain: 6)] {
        near(response(presetOf([b]), at: 1000, rate: 32000).left, 0, b.freq == 20000 ? 0 : 1e-12)
    }
}

@Test func autoCutsTheLoudestBoostAndNeverBoosts() {
    near(autoPreamp(presetOf([Band(gain: 6, q: 1)])), -6)
    #expect(autoPreamp(presetOf([Band(gain: -6, q: 1)])) == 0)
    #expect(peak(presetOf([Band(gain: 6, q: 1)]), rate: 48000).at == 1000)
}

@Test func aHandPreampOverFullScaleIsFlagged() {
    var loud = presetOf([Band(gain: 6, q: 1)], auto: false, preamp: -2)
    #expect(warnings(loud).joined(separator: " ").contains("Peaks reach 4 dB over full scale"))
    loud.preamp = -6
    #expect(warnings(loud) == [])
    loud.preamp = -2
    loud.auto = true
    #expect(warnings(loud) == [])
}

@Test func aLowShelfBoostUnder20HzIsNoReasonToWarn() {
    let shelf = presetOf([Band(type: .lowShelf, freq: 100, gain: 6, q: 0.7), Band(freq: 25, gain: -6, q: 1)],
                         auto: false, preamp: -5)
    #expect(warnings(shelf) == [])
    #expect(autoPreamp(shelf) < -5.9)
    #expect(peak(shelf, rate: 48000, low: 20).at >= 20)
}

@Test func aFlatPresetSaysSo() {
    #expect(warnings(.flat()).joined().contains("No band changes"))
}

@Test func namesFitTheCardAndTheQ2() {
    #expect(fileName("HD 600") == "HD 600.txt")
    #expect(fileName("a/b:c?") == "abc.txt")
    #expect(fileName(" ...trailing. ") == "trailing.txt")
    #expect(fileName("") == "My EQ.txt")
    #expect(fileName("con") == "EQ con.txt")
    #expect(cleanName(String(repeating: "é", count: 50)).utf8.count <= 60)
    #expect(nameOfFile("C:\\presets\\HD 600.txt") == "HD 600")
}

@Test func normalizeKeepsEveryValueInRange() {
    let wild = normalize(presetOf([Band(freq: 1, gain: 99, q: 99)])).bands[0]
    #expect(wild == Band(freq: 20, gain: 24, q: 10))
    let big = normalize(presetOf(Array(repeating: Band(), count: 40), preamp: -99, balance: 99))
    #expect(big.bands.count == EQ.maxBands)
    #expect(big.preamp == -60)
    #expect(big.balance == 12)
    #expect(normalize(presetOf([Band(freq: .nan, gain: .infinity)])).bands[0].freq == 1000)
}

@Test func noNumberHasAnExponentOrANegativeZero() {
    let text = serialize(presetOf([Band(gain: -0.0000001, q: 0.1)], auto: false, preamp: -0.0000001))
    #expect(text.firstMatch(of: try! Regex(#"\de|-0 "#)) == nil)
}

@Test func knobsAreTheirOwnShelves() throws {
    var p = Preset.flat()
    p = try #require(Knob.bass.set(6, in: p))
    #expect(Knob.bass.gain(in: p) == 6)
    #expect(Knob.of(p.bands.last!) == .bass)
    #expect(Knob.of(try read(serialize(p)).bands.last!) == .bass) // it lasts through a file
    p = try #require(Knob.bass.set(0, in: p))
    #expect(p.bands.count == 10)
}
