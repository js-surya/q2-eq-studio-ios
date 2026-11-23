// SPDX-License-Identifier: GPL-3.0-only
// Response, as EQ Studio's page has it (web/app.js): a reviewer's measurement of an earphone or headphone,
// from squig.link, drawn under the EQ and with the EQ added to it, and a target beside it. AutoEQ fits the
// bands to the target. Read by this device (the Q2 has no part in it); the measurement and the target are
// only drawn, never saved or sent. Kept for the next visit.
import EQCore
import Foundation
import Observation

typealias Curve = [(Double, Double)]

struct Shown {
    let base, file, name, by: String
    let points: Curve
}

struct SquigError: LocalizedError {
    let errorDescription: String?
    var status = 0
}

@MainActor @Observable
final class Response {
    static let maxBytes = 4 << 20 // the biggest phone book is about 300 KB, a measurement tens of KB
    private static let keptKey = "eq-studio-response"

    var sites: [Squig.Site]?
    var site = "superreview/" { didSet { keep(); Task { await load() } } }
    var books: [String: [Squig.Phone]] = [:]
    private var layouts: [String: Int] = [:]
    var loading = false
    var error: SquigError?
    var fetching = ""
    var target = Squig.targets[0].name { didSet { keep(); Task { await loadTarget() } } }
    var targets: [String: Curve] = [:]
    var shown: Shown?
    var fitting = false
    private var asked = 0

    var currentSite: Squig.Site? {
        guard let sites else { return nil }
        return sites.first { $0.id == site } ?? sites.first { $0.id == "superreview/" } ?? sites.first
    }

    var shownTarget: Curve? { shown != nil && !target.isEmpty ? targets[target] : nil }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 20
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    /// A file from squig.link: no cookies, a time limit, at most 4 MB.
    static func text(_ url: String, _ what: String) async throws -> String {
        guard let u = URL(string: url) else { throw SquigError(errorDescription: "squig.link doesn't have \(what).", status: 404) }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(from: u)
        } catch let e as URLError where e.code == .timedOut {
            throw SquigError(errorDescription: "squig.link didn't answer in time.")
        } catch {
            throw SquigError(errorDescription: "squig.link couldn't be reached. This device reads it, not the Q2, so it needs the internet.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SquigError(errorDescription: status == 404 ? "squig.link doesn't have \(what)." : "squig.link answered \(status) for \(what).", status: status)
        }
        if data.count > maxBytes { throw SquigError(errorDescription: "squig.link sent too much for \(what).") }
        return String(decoding: data, as: UTF8.self)
    }

    static func json(_ text: String) throws -> Any {
        guard let v = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else {
            throw SquigError(errorDescription: "squig.link's answer couldn't be read.")
        }
        return v
    }

    /// The reviewers once a visit, then the picked one's list, once each.
    func load() async {
        if loading { return }
        loading = true
        error = nil
        var id = ""
        do {
            if sites == nil {
                let list = Squig.sites(try Self.json(try await Self.text(Squig.sitesURL, "its list of reviewers")))
                if list.isEmpty { throw SquigError(errorDescription: "squig.link listed no reviewers.") }
                sites = list
            }
            let s = currentSite!
            id = s.id
            if books[s.id] == nil {
                books[s.id] = Squig.phones(try Self.json(try await Self.text(Squig.bookURL(s.base), "\(s.name)'s list")))
            }
        } catch {
            self.error = error as? SquigError ?? SquigError(errorDescription: error.localizedDescription)
        }
        loading = false
        // Another reviewer picked while this one loaded: that one now, and this one's error forgotten.
        if sites != nil, currentSite?.id != id {
            error = nil
            await load()
        }
    }

    var kindWord: String {
        guard let s = currentSite else { return "earphones" }
        return s.kind == "5128" ? "earphones" : s.kind == "IEMs" ? "in-ears" : s.kind.lowercased()
    }

    /// A search wants every word, in any order, in the name; the names where the first word comes earliest first.
    func found(_ search: String) -> [Squig.Phone] {
        guard let s = currentSite, let phones = books[s.id] else { return [] }
        let words = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let hits = phones.filter { p in words.allSatisfy { p.find.contains($0) } }
        guard let first = words.first else { return hits }
        let at = { (p: Squig.Phone) in p.find.range(of: first).map { p.find.distance(from: p.find.startIndex, to: $0.lowerBound) } ?? 0 }
        return hits.enumerated().sorted { a, b in
            let (x, y) = (at(a.element), at(b.element))
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }

    /// A measurement's sides, averaged, from wherever its site keeps them: the layout found last time there
    /// first. A side that's missing is a one-sided measurement; one that failed otherwise is an error. A pick
    /// from a database of a kind brings that kind's target. False when a later pick took over.
    func show(base: String, file: String, name: String, by: String, kind: String?) async throws -> Bool {
        asked += 1
        let mine = asked
        let known = layouts[base] ?? 0
        var order = [known]
        for k in Squig.layouts.indices where k != known { order.append(k) }
        for k in order {
            let urls = Squig.sideURLs(base, file, Squig.layouts[k])
            var texts: [Result<String, SquigError>] = []
            for url in urls {
                do { texts.append(.success(try await Self.text(url, "that measurement"))) } catch {
                    texts.append(.failure(error as? SquigError ?? SquigError(errorDescription: error.localizedDescription)))
                }
            }
            if mine != asked { return false }
            for t in texts { if case .failure(let e) = t, e.status != 404 { throw e } }
            let curves = texts.compactMap { if case .success(let s) = $0 { Squig.readCurve(s) } else { nil } }.filter { $0.count >= 2 }
            if !curves.isEmpty {
                layouts[base] = k
                shown = Shown(base: base, file: file, name: name, by: by, points: Squig.average(curves))
                if let kind { matchTarget(kind) }
                keep()
                await loadTarget()
                return true
            }
        }
        throw SquigError(errorDescription: "squig.link doesn't have \(name)'s measurement.", status: 404)
    }

    func clear() {
        shown = nil
        keep()
    }

    /// Headphones measure on other rigs than in-ears: a target for the one is wrong for the other, so a
    /// pick of another kind brings that kind's first target.
    private func matchTarget(_ kind: String) {
        guard let now = Squig.targets.first(where: { $0.name == target }) else { return }
        let want = kind == "Earbuds" ? "IEMs" : kind
        if now.kind == want { return }
        if let t = Squig.targets.first(where: { $0.kind == want }) { target = t.name }
    }

    /// The target's curve, from the first of its sites that answers, once a visit, 0 dB at 500 Hz as the
    /// measurement is. Its error, if none answered.
    @discardableResult
    func loadTarget() async -> String? {
        let name = target
        guard !name.isEmpty, shown != nil, targets[name] == nil, let t = Squig.targets.first(where: { $0.name == name }) else { return nil }
        var last: String?
        for url in t.urls {
            do {
                let points = Squig.readCurve(try await Self.text(url, "the \(name) target"))
                if points.count < 2 { throw SquigError(errorDescription: "squig.link's \(name) target isn't a curve.") }
                targets[name] = Squig.average([points])
                return nil
            } catch {
                last = error.localizedDescription
            }
        }
        return "The \(name) target couldn't be loaded. \(last ?? "")"
    }

    /// AutoEQ: the bands that bring the measurement to the target, as AutoEq shapes them, worked out off the
    /// main thread. nil when the measurement or the target changed while it waited.
    func autoEQ() async throws -> (preset: Preset, by: String)? {
        guard let measured = shown, !target.isEmpty, !fitting else { return nil }
        fitting = true
        defer { fitting = false }
        let to = target
        if targets[to] == nil { if let e = await loadTarget() { throw SquigError(errorDescription: e) } }
        guard let goal = targets[to], shown?.file == measured.file, target == to else { return nil }
        let points = measured.points
        let result = try await Task.detached(priority: .userInitiated) { try Fit.fit(measurement: [points], target: goal) }.value
        guard shown?.file == measured.file, target == to else { return nil }
        if result.bands.isEmpty { throw SquigError(errorDescription: "\(measured.name) is on \(to) already: no band would bring it closer.") }
        // The target in the name, unless a long name would lose it.
        let named = cleanName("\(measured.name) (\(to))")
        let name = named.hasSuffix("(\(cleanName(to)))") ? named : cleanName(measured.name)
        return (Preset(name: name, auto: true, preamp: 0, balance: 0, bands: result.bands), to)
    }

    // MARK: Kept for the next visit

    private func keep() {
        var kept: [String: Any] = ["site": site, "target": target]
        if let s = shown { kept["shown"] = ["base": s.base, "file": s.file, "name": s.name, "by": s.by] }
        if let d = try? JSONSerialization.data(withJSONObject: kept) { UserDefaults.standard.set(d, forKey: Self.keptKey) }
    }

    /// Last visit's reviewer and target, and its measurement fetched again; offline, it waits for the next
    /// visit. A note when it's gone from squig.link.
    func restore() async -> String? {
        guard let d = UserDefaults.standard.data(forKey: Self.keptKey),
              let kept = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if let s = kept["site"] as? String { site = s }
        if let t = kept["target"] as? String, t.isEmpty || Squig.targets.contains(where: { $0.name == t }) { target = t }
        guard let pick = kept["shown"] as? [String: String], let file = pick["file"], let name = pick["name"], let base = pick["base"],
              base.wholeMatch(of: /(?i)https:\/\/([a-z0-9-]+\.)?squig\.link\/([\w-]+\/)*/) != nil else { return nil }
        do {
            _ = try await show(base: base, file: file, name: name, by: pick["by"] ?? "its reviewer", kind: nil)
        } catch let e as SquigError where e.status == 404 {
            keep()
            return "\(name) is gone from squig.link, so it's off the graph."
        } catch {}
        return nil
    }
}
