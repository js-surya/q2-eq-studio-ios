// SPDX-License-Identifier: GPL-3.0-only
// squig.link: reviewers' frequency-response measurements, read by this device (the Q2 has no part in it)
// to show one under the EQ, as EQ Studio's web/squig.js reads them. squigsites.json lists the reviewers,
// each a site on squig.link with a database or more (in-ears, headphones...); a database's
// data/phone_book.json lists what it measured, and each side's measurement is a text file of
// frequencies and levels. Sites on other domains are left out, as the page leaves them out.
import Foundation

public enum Squig {
    public static let home = "https://squig.link"
    public static let sitesURL = "\(home)/squigsites.json"
    /// Each kind of database and its name, in the order the picker groups them.
    public static let kinds: [(kind: String, title: String)] = [("IEMs", "In-ears"), ("Headphones", "Headphones"), ("Earbuds", "Earbuds"), ("5128", "On a B&K 5128")]
    static let order = kinds.map(\.kind)

    static func host(_ type: String, _ user: String) -> String? {
        switch type {
        case "subdomain": "https://\(user).squig.link"
        case "labFolder": "\(home)/lab/\(user)"
        case "root": home
        default: nil
        }
    }

    public struct Site: Sendable, Hashable, Identifiable {
        public let id, name, kind, base: String
    }

    /// Sorts as JS's stable sort with localeCompare('en', { sensitivity: 'base' }).
    static func compareBase(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: Locale(identifier: "en"))
    }

    static func stableSorted<T>(_ items: [T], by less: (T, T) -> ComparisonResult) -> [T] {
        items.enumerated().sorted { x, y in
            let c = less(x.element, y.element)
            return c == .orderedSame ? x.offset < y.offset : c == .orderedAscending
        }.map(\.element)
    }

    /// The databases squigsites.json lists on squig.link, by kind then name.
    public static func sites(_ list: Any?) -> [Site] {
        var out: [Site] = []
        for item in list as? [Any] ?? [] {
            guard let site = item as? [String: Any] else { continue }
            let user = (site["username"]).map { "\($0)" } ?? ""
            guard user.wholeMatch(of: /(?i)[a-z0-9][a-z0-9-]*/) != nil, let type = site["urlType"] as? String,
                  let hostBase = host(type, user) else { continue }
            let dbs = (site["dbs"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.filter { db in
                guard let t = db["type"] as? String, order.contains(t) else { return false }
                return "\(db["folder"] ?? "")".wholeMatch(of: /\/([\w-]+\/)*/) != nil
            }
            for db in dbs {
                let type = db["type"] as! String, folder = "\(db["folder"]!)"
                let raw = (site["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? user
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                // A second database of the same kind is told apart by its folder.
                let twin = dbs.filter { ($0["type"] as? String) == type }.count > 1 && folder != "/"
                out.append(Site(id: "\(user)\(folder)", name: twin ? "\(name) (\(folder.dropFirst().dropLast()))" : name,
                                kind: type, base: "\(hostBase)\(folder)"))
            }
        }
        return stableSorted(out) { a, b in
            let k = order.firstIndex(of: a.kind)! - order.firstIndex(of: b.kind)!
            return k < 0 ? .orderedAscending : k > 0 ? .orderedDescending : compareBase(a.name, b.name)
        }
    }

    public struct Phone: Sendable, Hashable, Identifiable {
        public let name, file, find: String
        public var id: String { file }
    }

    static func starts(_ text: String, _ start: String) -> Bool { text.lowercased().hasPrefix(start.lowercased()) }

    /// A phone book as rows, one a measurement, named as squig.link names them: a model's variants by their
    /// suffix, by their file less its prefix, or by their file. Brands named _ something are the site's
    /// own (an EQ sandbox), not earphones.
    public static func phones(_ book: Any?) -> [Phone] {
        var out: [Phone] = []
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        for item in book as? [Any] ?? [] {
            let brand = item as? [String: Any]
            let maker = trim((brand?["name"]).map { "\($0)" } ?? "")
            if maker.hasPrefix("_") { continue }
            for entry in brand?["phones"] as? [Any] ?? [] {
                let phone = entry as? [String: Any]
                let model = trim(entry as? String ?? (phone?["name"]).map { "\($0)" } ?? "")
                let fileValue: Any? = entry is String ? entry : (phone?["file"] ?? phone?["name"])
                let files: [Any] = (fileValue as? [Any]) ?? (fileValue.map { [$0] } ?? [])
                let by = (phone?["collab"]).map { "\(maker) x \(trim("\($0)"))" } ?? maker
                let named = by.isEmpty || starts(model, by) ? model : "\(by) \(model)"
                for (index, f) in files.enumerated() {
                    guard let file = f as? String, !trim(file).isEmpty else { continue }
                    var name = named
                    if files.count > 1, let suffix = phone?["suffix"] as? [Any] {
                        name = "\(named) \(trim(index < suffix.count ? "\(suffix[index])" : ""))"
                    } else if files.count > 1, let prefix = phone?["prefix"] as? String {
                        name = "\(named) \(starts(file, prefix) ? trim(String(file.dropFirst(prefix.count))) : file)"
                    } else if files.count > 1 {
                        name = maker.isEmpty || starts(file, maker) ? file : "\(maker) \(file)"
                    }
                    name = trim(name)
                    if !name.isEmpty { out.append(Phone(name: name, file: file, find: name.lowercased())) }
                }
            }
        }
        return stableSorted(out) { compareBase($0.name, $1.name) }
    }

    public static func bookURL(_ base: String) -> String { "\(base)data/phone_book.json" }

    /// Where sites keep a side's file: most in data/, some in a folder of it, some as numbered samples
    /// (L1, L2...: the first is taken).
    public static let layouts: [(dir: String, sample: String)] = [("data/", ""), ("data/", "1"), ("data/phones/", ""),
                                                                    ("data/measurements/", ""), ("data/phones/", "1"), ("data/measurements/", "1")]

    /// JS's encodeURIComponent.
    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    public static func sideURLs(_ base: String, _ file: String, _ layout: (dir: String, sample: String)) -> [String] {
        ["L", "R"].map { "\(base)\(layout.dir)\(encode("\(file) \($0)\(layout.sample).txt"))" }
    }

    /// A measurement as text: a frequency and a level a line, a phase after them ignored, other lines
    /// (notes, headings) skipped.
    public static func readCurve(_ text: String) -> [(Double, Double)] {
        var points: [(Double, Double)] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            guard parts.count >= 2, let f = Double(parts[0]), let level = Double(parts[1]), f.isFinite, level.isFinite, f > 0 else { continue }
            points.append((f, level))
        }
        return stableSorted(points) { $0.0 < $1.0 ? .orderedAscending : $0.0 > $1.0 ? .orderedDescending : .orderedSame }
    }

    /// A curve's level at f: straight between its points on a log scale, flat past its ends.
    public static func at(_ points: [(Double, Double)], _ f: Double) -> Double {
        var (low, high) = (0, points.count - 1)
        if f <= points[low].0 { return points[low].1 }
        if f >= points[high].0 { return points[high].1 }
        while high - low > 1 {
            let mid = (low + high) >> 1
            if points[mid].0 <= f { low = mid } else { high = mid }
        }
        let ((f0, a), (f1, b)) = (points[low], points[high])
        return f1 == f0 ? a : a + (b - a) * log(f / f0) / log(f1 / f0)
    }

    /// The 1/48-octave grid squig.link's curves are averaged on.
    public static let grid: [Double] = {
        var out: [Double] = []
        var f = 20.0
        while f <= 20000 { out.append(f); f *= pow(2, 1.0 / 48) }
        return out
    }()

    /// The sides averaged on the grid, 0 dB at 500 Hz, where squig.link lines curves up (the IEC's choice),
    /// so the EQ's 0 dB line sits there.
    public static func average(_ curves: [[(Double, Double)]]) -> [(Double, Double)] {
        let level = { (f: Double) in curves.reduce(0) { $0 + at($1, f) } / Double(curves.count) }
        let centre = level(500)
        return grid.map { ($0, level($0) - centre) }
    }

    // Targets: PEQdB Studio's (less its own) and squig.link's own, each from squig.link sites that keep
    // it, the first that answers taken. Grouped by the rig they're for: a target is drawn on one.
    public static let targetKinds: [(kind: String, title: String)] = [("IEMs", "For in-ears"), ("Headphones", "For headphones"), ("5128", "For a B&K 5128")]

    public struct Target: Sendable, Hashable, Identifiable {
        public let kind, name: String
        public let urls: [String]
        public var id: String { name }
    }

    static func file(_ base: String, _ name: String) -> String { "\(base)\(encode("\(name) Target.txt"))" }
    static func sub(_ user: String, _ folder: String = "") -> String { "https://\(user).squig.link/\(folder)data/" }
    static let main = "\(home)/data/"

    public static let targets: [Target] = [
        Target(kind: "IEMs", name: "Harman IE 2019", urls: [file(main, "Harman IE 2019")]),
        Target(kind: "IEMs", name: "∆ JM-1 −10dB Tilt", urls: ["theaudiostore", "bloomaudio", "bassaudio"].map { file(sub($0), "∆ JM-1 for 711 - 10dB Tilt") }),
        Target(kind: "IEMs", name: "IEF Preference 2025", urls: ["fahryst", "gadgetrytech"].map { file(sub($0), "IEF Preference 2025") }),
        Target(kind: "IEMs", name: "Knowles", urls: [file("\(home)/lab/jaraba/data/", "Knowles")]),
        Target(kind: "IEMs", name: "Moondrop VDSF", urls: ["bedrock", "fahryst"].map { file(sub($0), "Moondrop VDSF") }),
        Target(kind: "IEMs", name: "∆ Harman MoA 2025", urls: [file(main, "∆ Harman MoA 2025")]),
        Target(kind: "IEMs", name: "Super 22", urls: [file(main, "Super 22")]),
        Target(kind: "IEMs", name: "Crinacle 2023 Adjusted", urls: [file(main, "Crinacle 2023 Adjusted")]),
        Target(kind: "IEMs", name: "Diffuse Field", urls: [file(main, "Diffuse Field")]),
        Target(kind: "Headphones", name: "Harman OE 2018", urls: [file("\(sub("filk"))targets/", "Harman OE 2018"), file("\(sub("kr0mka", "headphones/"))targets/", "Harman OE 2018")]),
        Target(kind: "Headphones", name: "Harman OE 2018 Linear Bass", urls: [file(sub("iemworld", "headphones/"), "Harman OE 2018 Linear"), file(sub("kuulokenurkka"), "Harman 2018 With Linear Bass")]),
        Target(kind: "Headphones", name: "Harman OE 2013", urls: [file("\(home)/lab/elrics/headphones/data/targets/", "Harman OE 2013"), file("\(sub("kr0mka", "headphones/"))targets/", "Harman OE 2013")]),
        Target(kind: "Headphones", name: "KEMAR KB50xx −10dB Tilt", urls: ["audioamigo", "boizoff"].map { file(sub($0, "headphones/"), "10dB Tilt KEMAR DF (KB50xx)") }),
        Target(kind: "Headphones", name: "KEMAR KB006x −10dB Tilt", urls: [file("\(home)/headphones/data/", "KEMAR DF (KB006x) 10dB Tilt")]),
        Target(kind: "5128", name: "∆ 5128DF −10dB Tilt", urls: [file(main, "∆ 5128DF - 10dB Tilt")]),
        Target(kind: "5128", name: "∆ 5128DF", urls: [file(main, "∆ 5128DF")]),
    ]
}
