// SPDX-License-Identifier: GPL-3.0-only
// EQ Studio's web/squig.test.mjs and web/fit.test.mjs, case for case: squig.link's site list, phone books
// and measurements as read, and the fit finding a known EQ again.
import Foundation
import Testing
@testable import EQCore

@Test func sitesByKindThenNameOthersLeftOut() {
    let list = Squig.sites([
        ["username": "precog", "name": "Precogvision", "urlType": "subdomain", "dbs": [["type": "IEMs", "folder": "/"]]],
        ["username": "hana", "name": "Hana", "urlType": "labFolder", "dbs": [["type": "IEMs", "folder": "/"]]],
        ["username": "superreview", "name": "Super* Review", "urlType": "root", "dbs": [["type": "Headphones", "folder": "/headphones/"], ["type": "IEMs", "folder": "/"]]],
        ["username": "crinacle", "name": "Hangout.Audio", "urlType": "altDomain", "altDomain": "https://graph.hangout.audio", "dbs": [["type": "IEMs", "folder": "/iem/711/"]]],
        ["username": "two", "name": "Two", "urlType": "subdomain", "dbs": [["type": "IEMs", "folder": "/"], ["type": "IEMs", "folder": "/b/"]]],
        ["username": "bad.host", "name": "Bad", "urlType": "subdomain", "dbs": [["type": "IEMs", "folder": "/"]]],
        ["username": "odd", "name": "Odd", "urlType": "subdomain", "dbs": [["type": "IEMs", "folder": "/../x/"], ["type": "toString", "folder": "/"]]],
        ["username": "proto", "name": "Proto", "urlType": "constructor", "dbs": [["type": "IEMs", "folder": "/"]]],
        ["username": "rig", "name": "Rig", "urlType": "subdomain", "dbs": [["type": "5128", "folder": "/"]]],
    ] as [Any])
    #expect(list.map { "\($0.kind)|\($0.name)|\($0.base)" } == [
        "IEMs|Hana|https://squig.link/lab/hana/",
        "IEMs|Precogvision|https://precog.squig.link/",
        "IEMs|Super* Review|https://squig.link/",
        "IEMs|Two|https://two.squig.link/",
        "IEMs|Two (b)|https://two.squig.link/b/",
        "Headphones|Super* Review|https://squig.link/headphones/",
        "5128|Rig|https://rig.squig.link/",
    ])
    #expect(Squig.sites(nil).isEmpty)
}

@Test func phonesNamedAsSquigLinkNamesThem() {
    let rows = Squig.phones([
        ["name": "_EQ", "phones": [["name": "Sandbox", "file": "EQ sandbox"]]],
        ["name": "64 Audio", "phones": [["name": "U12t", "file": "64 Audio U12t"], ["name": "64 Audio Nio", "file": ["Nio m15", "Nio m20"], "suffix": ["(m15)", ""]]]],
        ["name": "Kinera", "phones": [["name": "Verdandi TWS", "file": ["Kinera Verdandi TWS (aptX)", "Kinera Verdandi TWS (SBC)"], "prefix": "Kinera Verdandi TWS"]]],
        ["name": "qdc", "phones": [["name": "Anole VX", "file": ["Anole VX (DDD)", "qdc Anole VX (DDB)"]], ["name": "Tiger"]]],
        ["name": "Moondrop", "phones": ["Aria", ["name": "Dusk", "collab": "Crinacle", "file": "Dusk"], ["name": "Bad", "file": 7]] as [Any]],
    ] as [Any])
    #expect(rows.map { "\($0.name)|\($0.file)" } == [
        "64 Audio Nio|Nio m20", "64 Audio Nio (m15)|Nio m15", "64 Audio U12t|64 Audio U12t",
        "Kinera Verdandi TWS (aptX)|Kinera Verdandi TWS (aptX)", "Kinera Verdandi TWS (SBC)|Kinera Verdandi TWS (SBC)",
        "Moondrop Aria|Aria", "Moondrop x Crinacle Dusk|Dusk", "qdc Anole VX (DDB)|qdc Anole VX (DDB)",
        "qdc Anole VX (DDD)|Anole VX (DDD)", "qdc Tiger|Tiger",
    ])
    #expect(Squig.phones([String: Any]()).isEmpty)
}

@Test func aMeasurementsAddressesNameEncoded() {
    let base = "https://precog.squig.link/"
    #expect(Squig.bookURL(base) == "https://precog.squig.link/data/phone_book.json")
    #expect(Squig.sideURLs(base, "Tin #1?", Squig.layouts[0]) == ["https://precog.squig.link/data/Tin%20%231%3F%20L.txt", "https://precog.squig.link/data/Tin%20%231%3F%20R.txt"])
    #expect(Squig.sideURLs(base, "HD 600", ("data/phones/", "1")) == ["https://precog.squig.link/data/phones/HD%20600%20L1.txt", "https://precog.squig.link/data/phones/HD%20600%20R1.txt"])
}

@Test func readCurveTakesREWText() {
    let p = Squig.readCurve("* Measurement data measured by REW\n* Note:\n20.5\t101.2\t170.1\n1000, 98.5\nfrequency,raw\n500 99\n")
    #expect(p.map { [$0.0, $0.1] } == [[20.5, 101.2], [500, 99], [1000, 98.5]])
    #expect(Fit.readCurve("20.5\t101.2\r\n500 99\r\n").count == 2)
}

@Test func averageOnALogGridZeroAt500() {
    let curve = Squig.average([[(100, 90), (1000, 100), (10000, 110)], [(100, 94), (1000, 104), (10000, 114)]])
    let level = { (f: Double) in Squig.at(curve, f) }
    #expect(abs(level(500)) < 0.05)
    #expect(abs(level(100) - level(1000) + 10) < 0.05)
    #expect(abs(level(20) - level(100)) < 0.05 && abs(level(20000) - level(10000)) < 0.05)
    #expect(Squig.at([(100, 1), (100, 3), (200, 5)], 100) == 1)
}

@Test func targetsEachKindNamedOnceOnSquigLink() {
    let names = Squig.targets.map(\.name)
    #expect(Set(names).count == names.count)
    for k in Squig.targetKinds { #expect(Squig.targets.contains { $0.kind == k.kind }, "\(k.kind)") }
    for t in Squig.targets {
        #expect(!t.urls.isEmpty)
        for u in t.urls {
            let url = URL(string: u)!
            #expect(url.scheme == "https" && url.host()!.wholeMatch(of: /([a-z0-9-]+\.)?squig\.link/) != nil, "\(u)")
            #expect(url.absoluteString.hasSuffix("%20Target.txt") && !url.absoluteString.contains("%2F"), "\(u)")
        }
    }
}

// MARK: The fit

private func level(_ bands: [Band], _ f: Double) -> Double { bands.reduce(0) { $0 + bandResponse($1, at: f) } }
private func curve(_ shape: (Double) -> Double) -> [(Double, Double)] {
    Fit.freqs.enumerated().filter { $0.offset % 4 == 0 }.map { ($0.element, shape($0.element)) }
}
/// A target with a bass shelf and an ear-gain bump, as in-ear targets have.
private let targetBands = [Band(type: .lowShelf, freq: 105, gain: 6, q: 0.7), Band(freq: 2800, gain: 8, q: 1)]
private let target = curve { level(targetBands, $0) }

@Test func theFitFindsAKnownEQAgain() throws {
    let known = [Band(type: .lowShelf, freq: 105, gain: -4, q: 0.7), Band(freq: 3000, gain: 5, q: 2), Band(freq: 6000, gain: -3, q: 3), Band(freq: 300, gain: 2, q: 1)]
    let measured = curve { 90 + level(targetBands, $0) - level(known, $0) }
    let r = try Fit.fit(measurement: [measured, measured], target: target)
    #expect(r.rms < 0.3, "rms \(r.rms)")
    let offset = level(r.bands, 1000) - level(known, 1000)
    for f in [40.0, 100, 300, 1000, 3000, 6000, 8000] {
        #expect(abs(level(r.bands, f) - level(known, f) - offset) < 1, "\(f) Hz: \(level(r.bands, f)) vs \(level(known, f))")
    }
}

@Test func theQ2TakesEveryBandItFits() throws {
    let measured = curve { 95 + 10 * sin(log2($0) * 2) }
    let r = try Fit.fit(measurement: [measured], target: target)
    #expect(r.bands.count <= 10)
    for b in r.bands {
        #expect(b.freq >= EQ.freqMin && b.freq <= 10000, "freq \(b.freq)")
        #expect(abs(b.gain) <= 12 && b.q >= 0.4 && b.q <= 6, "gain \(b.gain) q \(b.q)")
    }
}

@Test func past10kHzNoChangeAndBoostsStopAtMax() throws {
    let measured = curve { f in 90 + level(targetBands, f) + (f > 12000 && f < 16000 ? -10 : 0) + level([Band(freq: 1500, gain: -15, q: 0.8)], f) }
    let r = try Fit.fit(measurement: [measured], target: target, maxBoost: 6)
    for f in [12000.0, 14000, 16000] { #expect(abs(level(r.bands, f)) < 3, "\(f) Hz: \(level(r.bands, f))") }
    let most = Fit.freqs.map { level(r.bands, $0) }.max()!
    #expect(most - level(r.bands, 1000) < 7 + 6)
}

@Test func oneSideIsEnoughNoneIsSaid() throws {
    let measured = curve { 90 + level(targetBands, $0) }
    #expect(try Fit.fit(measurement: [[], measured], target: target).rms < 0.5)
    #expect(throws: Fit.NoCurve.self) { try Fit.fit(measurement: [[], []], target: target) }
}
