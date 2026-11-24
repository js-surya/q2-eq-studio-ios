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
    var target = Squig.targets[0].name { didSet { lines(); keep(); Task { await loadTarget() } } }
    var targets: [String: Curve] = [:] { didSet { lines() } }
    var shown: Shown? { didSet { lines() } }

    /// The measurement and the target at the graph's points, worked out when they change.
    private(set) var measuredLine: [Double]?
    private(set) var targetLine: [Double]?

    private func lines() {
        measuredLine = shown.map { m in Plot.freqs.map { Squig.at(m.points, $0) } }
        targetLine = shownTarget.map { t in Plot.freqs.map { Squig.at(t, $0) } }
    }
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

    /// A search wants every word, in any order, in the name, dashes, spaces and capitals aside ("wf1000xm4"
    /// finds "WF-1000XM4"); the names where the first word comes earliest first.
    func found(_ search: String) -> [Squig.Phone] {
        guard let s = currentSite, let phones = books[s.id] else { return [] }
        let words = Self.words(search)
        guard let first = words.first else { return phones }
        let keys = keyed(s.id)
        var hits: [(phone: Squig.Phone, at: Int, order: Int)] = []
        for (k, key) in keys.enumerated() where words.allSatisfy({ key.contains($0) }) {
            let at = key.range(of: first).map { key.distance(from: key.startIndex, to: $0.lowerBound) } ?? 0
            hits.append((phones[k], at, k))
        }
        return hits.sorted { $0.at == $1.at ? $0.order < $1.order : $0.at < $1.at }.map(\.phone)
    }

    // MARK: Every reviewer's list, for a search across them all

    /// Every list read (or being read), so "Measured by" can narrow to the reviewers who have a match.
    private(set) var everyLoaded = false
    private(set) var everyLoading = false
    /// Each list's names squashed for matching, worked out once.
    @ObservationIgnored private var keys: [String: [String]] = [:]
    @ObservationIgnored private var memo: (search: String, lists: Int, counts: [String: Int])?
    private static let listsFile = URL.cachesDirectory.appending(path: "squig-lists.json")
    private static let listsKeep: TimeInterval = 24 * 3600

    /// Lowercased, letters and digits only.
    static func squash(_ s: String) -> String {
        String(String.UnicodeScalarView(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    static func words(_ search: String) -> [String] {
        search.split(whereSeparator: \.isWhitespace).map { squash(String($0)) }.filter { !$0.isEmpty }
    }

    private func keyed(_ id: String) -> [String] {
        if let k = keys[id], k.count == books[id]?.count { return k }
        let k = (books[id] ?? []).map { Self.squash($0.name) }
        keys[id] = k
        return k
    }

    /// How many of each reviewer's measurements match, for the reviewers with one at least.
    func reviewers(matching search: String) -> [String: Int] {
        let words = Self.words(search)
        guard !words.isEmpty else { return [:] }
        if let m = memo, m.search == search, m.lists == books.count { return m.counts }
        var counts: [String: Int] = [:]
        for id in books.keys {
            let n = keyed(id).reduce(0) { n, key in words.allSatisfy { key.contains($0) } ? n + 1 : n }
            if n > 0 { counts[id] = n }
        }
        memo = (search, books.count, counts)
        return counts
    }

    /// Every reviewer's list: kept on this device a day, else read from squig.link ten at a time (about
    /// 0.6 MB in all). A list that fails is left out.
    func loadEvery() async {
        guard !everyLoaded, !everyLoading else { return }
        // The reviewers first: waited for when the tab's own load is reading them.
        while sites == nil {
            if loading { try? await Task.sleep(for: .milliseconds(100)) } else { await load(); if sites == nil { return } }
            if Task.isCancelled { return }
        }
        guard let sites else { return }
        everyLoading = true
        defer { everyLoading = false }
        readLists()
        let missing = sites.filter { books[$0.id] == nil }
        if !missing.isEmpty {
            await withTaskGroup(of: (String, [Squig.Phone]?).self) { group in
                var next = 0, inFlight = 0
                while next < missing.count || inFlight > 0 {
                    while inFlight < 10 && next < missing.count { // ten at a time
                        let id = missing[next].id, base = missing[next].base
                        next += 1
                        inFlight += 1
                        group.addTask { (id, await Response.list(base)) }
                    }
                    guard let (id, phones) = await group.next() else { break }
                    inFlight -= 1
                    if let phones, books[id] == nil { books[id] = phones }
                }
            }
            writeLists()
        }
        everyLoaded = true
    }

    /// One reviewer's list, off the main thread, as text() reads files: no cookies, a time limit, 4 MB at most.
    nonisolated private static func list(_ base: String) async -> [Squig.Phone]? {
        guard let url = URL(string: Squig.bookURL(base)),
              let (data, response) = try? await listSession.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4 << 20,
              let v = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return Squig.phones(v)
    }

    nonisolated private static let listSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 20
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    /// A pull on the Response tab: the reviewers and every list read again from squig.link, the copy kept
    /// on this device dropped. The measurement on the graph stays.
    func refresh() async {
        guard !loading, !everyLoading else { return }
        try? FileManager.default.removeItem(at: Self.listsFile)
        sites = nil
        books = [:]
        keys = [:]
        memo = nil
        everyLoaded = false
        await load()
    }

    private func readLists() {
        guard let d = try? Data(contentsOf: Self.listsFile),
              let kept = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let saved = kept["saved"] as? Double, Date().timeIntervalSince1970 - saved < Self.listsKeep,
              let lists = kept["lists"] as? [String: [[String]]] else { return }
        // The picked reviewer's list is read fresh each launch, never this copy.
        for (id, rows) in lists where books[id] == nil && id != currentSite?.id {
            books[id] = rows.compactMap { $0.count == 2 ? Squig.Phone(name: $0[0], file: $0[1], find: $0[0].lowercased()) : nil }
        }
    }

    private func writeLists() {
        let lists = books.mapValues { $0.map { [$0.name, $0.file] } }
        let kept: [String: Any] = ["saved": Date().timeIntervalSince1970, "lists": lists]
        if let d = try? JSONSerialization.data(withJSONObject: kept) { try? d.write(to: Self.listsFile, options: .atomic) }
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
