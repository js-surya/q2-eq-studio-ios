// SPDX-License-Identifier: GPL-3.0-only
// AutoEq's presets as EQ Studio serves them (GET /presets.json): Theme Studio's docs/presets.json.

import Foundation

public struct Catalogue: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Identifiable, Hashable {
        public let name: String
        public let source: String
        public let type: String
        public let text: String
        /// Its place on the short list before a search, if it has one: the page reads it as truthy.
        public let top: Int?
        public var id: String { "\(name)\u{1}\(source)" }

        enum CodingKeys: String, CodingKey { case name, source, type, text, top }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            source = try c.decode(String.self, forKey: .source)
            type = try c.decode(String.self, forKey: .type)
            text = try c.decode(String.self, forKey: .text)
            if let n = try? c.decodeIfPresent(Int.self, forKey: .top) { top = n == 0 ? nil : n }
            else if let b = try? c.decodeIfPresent(Bool.self, forKey: .top) { top = b ? 1 : nil }
            else { top = nil }
        }
    }

    public let credit: String
    public let commit: String?
    public let presets: [Entry]
    /// The 25 picked to show before a search, in their order.
    public let top: [Entry]
    /// Each preset's name and source in lower case, worked out once for searching.
    private let hay: [String]

    enum CodingKeys: String, CodingKey { case credit, commit, presets }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        credit = try c.decode(String.self, forKey: .credit)
        commit = try c.decodeIfPresent(String.self, forKey: .commit)
        presets = try c.decode([Entry].self, forKey: .presets)
        top = presets.filter { $0.top != nil }.sorted { $0.top! < $1.top! }
        hay = presets.map { "\($0.name) \($0.source)".lowercased() }
    }

    public init(json: Data) throws { self = try JSONDecoder().decode(Catalogue.self, from: json) }

    /// Every word of the search in the name or the source, in any case; at most limit.
    public func search(_ text: String, type: String? = nil, limit: Int = .max) -> [Entry] {
        let terms = text.lowercased().split(separator: " ").map(String.init)
        var out: [Entry] = []
        for (i, entry) in presets.enumerated() where type == nil || entry.type == type {
            if terms.allSatisfy({ hay[i].contains($0) }) {
                out.append(entry)
                if out.count == limit { break }
            }
        }
        return out
    }
}
