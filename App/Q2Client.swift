// SPDX-License-Identifier: GPL-3.0-only
// Talking to EQ Studio on the Q2: the same JSON API its own page uses (web.go in q2-eq-studio), signed
// in with the key its QR code carries or the PIN on the Q2's screen, sent as the page's cookie.
import Foundation
import Security

/// Where EQ Studio is, and the key that signs this device in.
struct Q2Link: Equatable, Sendable {
    var base: URL
    var key: String

    static let port = 8020

    /// EQ Studio's QR code: http://<ip>:<port>/?k=<key>.
    init?(scanned text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "http" || parts.scheme == "https", parts.host?.isEmpty == false,
              let key = parts.queryItems?.first(where: { $0.name == "k" })?.value, !key.isEmpty,
              let base = Q2Link.base(of: parts) else { return nil }
        self.base = base
        self.key = key
    }

    init(base: URL, key: String) {
        self.base = base
        self.key = key
    }

    private static func base(of parts: URLComponents) -> URL? {
        var b = URLComponents()
        (b.scheme, b.host, b.port) = (parts.scheme, parts.host, parts.port)
        return b.url
    }

    /// The address as typed under the QR code: 192.168.1.20:8020, with or without http://.
    static func base(typed text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if !t.contains("://") { t = "http://" + t }
        guard var parts = URLComponents(string: t), parts.host?.isEmpty == false else { return nil }
        if parts.port == nil { parts.port = port }
        parts.path = ""
        parts.query = nil
        return base(of: parts)
    }

    var address: String {
        guard let host = base.host() else { return base.absoluteString }
        return base.port.map { "\(host):\($0)" } ?? host
    }
}

enum Q2Error: LocalizedError, Equatable {
    case unreachable, timeout, signIn, local
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .unreachable: "Can't reach the Q2. Check that it's on, EQ Studio is open on it, and this device is on the same Wi-Fi."
        case .timeout: "The Q2 didn't answer in time."
        case .signIn: "This device isn't signed in to EQ Studio any more. Scan the Q2's code again."
        case .local: "This Q2 Pod can't take an EQ from the phone: update it."
        case .refused(let why): why
        }
    }
}

struct Q2State: Decodable, Sendable {
    let live: Bool
    let mode: String?
    let preset: String?
    let error: String?
}

struct CardFile: Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let file: String
    let size: Int64
    let mtime: Int64
    var id: String { file }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(mtime)) }
}

/// The Q2's answer to an EQ or an on/off: ok with what now plays, or its reason.
struct SendResult: Decodable, Sendable {
    let ok: Bool
    let mode: String?
    let error: String?
}

struct Q2Client: Sendable {
    let link: Q2Link

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil // the key goes as the page's cookie, set here, never stored elsewhere
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 10
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Q2Error.unreachable }
            return (data, http)
        } catch let error as URLError where error.code == .timedOut {
            throw Q2Error.timeout
        } catch let error as Q2Error {
            throw error
        } catch {
            throw Q2Error.unreachable
        }
    }

    private static func problem(_ data: Data, _ http: HTTPURLResponse) -> Q2Error {
        struct Body: Decodable { let error: String? }
        let why = (try? JSONDecoder().decode(Body.self, from: data))?.error
        return .refused(why ?? "The Q2 answered \(http.statusCode).")
    }

    /// The PIN on the Q2's screen for the key it keeps in its cookie: ten wrong ones lock it a minute.
    static func signIn(base: URL, pin: String) async throws -> Q2Link {
        var r = URLRequest(url: base.appending(path: "api/login"))
        r.httpMethod = "POST"
        r.setValue("1", forHTTPHeaderField: "X-Q2")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(["pin": pin])
        let (data, http) = try await send(r)
        guard http.statusCode == 200 else { throw problem(data, http) }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: http.allHeaderFields as? [String: String] ?? [:], for: base)
        guard let key = cookies.first(where: { $0.name == "q2eq" })?.value else { throw Q2Error.refused("The Q2 didn't sign this device in.") }
        return Q2Link(base: base, key: key)
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                         type: String? = nil, timeout: TimeInterval = 10) async throws -> (Data, HTTPURLResponse) {
        var url = link.base.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue("1", forHTTPHeaderField: "X-Q2")
        r.setValue("q2eq=\(link.key)", forHTTPHeaderField: "Cookie")
        if let type { r.setValue(type, forHTTPHeaderField: "Content-Type") }
        r.httpBody = body
        let (data, http) = try await Q2Client.send(r)
        if http.statusCode == 401 { throw Q2Error.signIn }
        return (data, http)
    }

    private func decode<T: Decodable>(_ data: Data, _ http: HTTPURLResponse) throws -> T {
        guard (200..<300).contains(http.statusCode) else { throw Q2Client.problem(data, http) }
        guard let v = try? JSONDecoder().decode(T.self, from: data) else { throw Q2Error.refused("The Q2's answer couldn't be read.") }
        return v
    }

    /// Whether the Q2 takes the EQ live and, if it does, what it has now.
    func state() async throws -> Q2State {
        let (d, h) = try await request("GET", "api/state")
        return try decode(d, h)
    }

    /// A preset's text, to play at once. .local when the firmware has no live EQ.
    func putEQ(_ text: String) async throws -> SendResult {
        let (d, h) = try await request("PUT", "api/eq", body: Data(text.utf8), type: "text/plain; charset=utf-8")
        if h.statusCode == 503 { throw Q2Error.local }
        return try decode(d, h)
    }

    func putMode(on: Bool) async throws -> SendResult {
        let (d, h) = try await request("PUT", "api/mode", body: try JSONEncoder().encode(["on": on]), type: "application/json")
        if h.statusCode == 503 { throw Q2Error.local }
        return try decode(d, h)
    }

    func cardList() async throws -> [CardFile] {
        struct List: Decodable { let files: [CardFile] }
        let (d, h) = try await request("GET", "api/card")
        let list: List = try decode(d, h)
        return list.files
    }

    func cardGet(_ file: String) async throws -> String {
        let (d, h) = try await request("GET", "api/card/file", query: [URLQueryItem(name: "name", value: file)])
        guard h.statusCode == 200 else { throw Q2Client.problem(d, h) }
        return String(decoding: d, as: UTF8.self)
    }

    /// Saves to the card's EQ folder; .refused with 409's words when the name is taken and replace is off.
    func cardPut(_ file: String, text: String, replace: Bool) async throws -> Bool {
        var q = [URLQueryItem(name: "name", value: file)]
        if replace { q.append(URLQueryItem(name: "replace", value: "1")) }
        let (d, h) = try await request("PUT", "api/card/file", query: q, body: Data(text.utf8), type: "text/plain; charset=utf-8")
        if h.statusCode == 409 { return false }
        guard h.statusCode == 200 else { throw Q2Client.problem(d, h) }
        return true
    }

    func cardDelete(_ file: String) async throws {
        let (d, h) = try await request("DELETE", "api/card/file", query: [URLQueryItem(name: "name", value: file)])
        guard h.statusCode == 200 else { throw Q2Client.problem(d, h) }
    }

    /// AutoEq's catalogue, gzipped on the card; URLSession unzips it.
    func presets() async throws -> Data {
        let (d, h) = try await request("GET", "presets.json", timeout: 60)
        guard h.statusCode == 200 else { throw Q2Client.problem(d, h) }
        return d
    }
}

/// The link kept between launches: the addresses in the defaults, the key in the keychain. A Q2 keeps
/// one key whichever way it's reached, so its Wi-Fi address and its Tailscale one are both kept, the one
/// that last answered first, and the app moves to another when one stops answering.
enum LinkStore {
    private static let addressesKey = "q2.bases"
    private static let service = "EQ Studio"
    private static let account = "q2"

    static var addresses: [URL] {
        (UserDefaults.standard.stringArray(forKey: addressesKey) ?? []).compactMap(URL.init(string:))
    }

    static func load() -> Q2Link? {
        guard let base = addresses.first else { return nil }
        var item: CFTypeRef?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return Q2Link(base: base, key: String(decoding: data, as: UTF8.self))
    }

    /// The link, its address first. A new key is another Q2 (or a new key on it): the old addresses go.
    static func save(_ link: Q2Link) {
        let same = load()?.key == link.key
        var list = same ? addresses.filter { $0 != link.base } : []
        list.insert(link.base, at: 0)
        UserDefaults.standard.set(Array(list.prefix(4)).map(\.absoluteString), forKey: addressesKey)
        if !same {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecValueData as String: Data(link.key.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: addressesKey)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
