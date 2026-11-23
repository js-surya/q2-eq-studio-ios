// SPDX-License-Identifier: GPL-3.0-only
// About: what this is, the Q2 it's signed in to, everyone whose work it stands on, and every
// contributor to Q2 Pod by their GitHub name, read from GitHub (the list built in when offline).
import SwiftUI

/// Settings: the Q2 this device is signed in to, the look, the graph's extras, the keys, and About.
struct SettingsView: View {
    @Environment(Studio.self) private var studio
    @State private var confirmDisconnect = false
    @State private var addAddress = false
    @State private var showAbout = false

    var body: some View {
        @Bindable var studio = studio
        Form {
            if let link = studio.link {
                Section {
                    LabeledContent("Address", value: link.address)
                    if studio.addresses.count > 1 {
                        LabeledContent("Also Reached At", value: studio.addresses.filter { $0 != link.base }
                            .map { Q2Link(base: $0, key: "").address }.joined(separator: ", "))
                    }
                    LabeledContent("Live EQ", value: studio.live.local ? "Not on this Q2 Pod" : studio.live.on ? "On" : "—")
                    Button("Add Another Address…", systemImage: "plus") { addAddress = true }
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmDisconnect = true }
                } header: {
                    Text("Q2")
                } footer: {
                    Text("Away from the Q2's Wi-Fi, add its Tailscale address: Tailscale on the Q2 shows it under Settings → Apps Shared Now.")
                }
            }
            Section("Appearance") {
                ThemePicker()
            }
            Section {
                Toggle("Each Band's Curve", isOn: $studio.showEachBand)
                if Device.hasPointer { Toggle("Inspect", isOn: $studio.inspect) }
            } header: {
                Text("Graph")
            } footer: {
                if Device.hasPointer { Text("Inspect shows a line where the pointer is on the graph, and the gain there.") }
            }
            Section {
                if Device.hasPointer { Button("Keyboard and Mouse", systemImage: "keyboard") { studio.showKeys = true } }
                NavigationLink(value: "about") {
                    Label("About EQ Studio", systemImage: "info.circle")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .navigationDestination(for: String.self) { _ in AboutView() }
        .navigationDestination(isPresented: $showAbout) { AboutView() }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["EQS_TAB"] == "about" { showAbout = true } }
        #endif
        .sheet(isPresented: $addAddress) { SignInForm() }
        .confirmationDialog("Sign out of this Q2?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { studio.disconnect() }
        } message: {
            Text("To come back, scan the Q2's code again.")
        }
    }
}

/// About: what this is, who made it, whose work it stands on, and every contributor to Q2 Pod by their
/// GitHub name, read from GitHub (the list built in when offline).
struct AboutView: View {
    @State private var contributors: [Contributor] = Contributor.kept

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("StudioIcon")
                        .resizable()
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)
                    Text("EQ Studio").font(.title2.bold())
                    Text(version).font(.subheadline).foregroundStyle(.secondary)
                    Text("A native app for EQ Studio, the Q2 Pod app by Bond. It edits the same EQ, through EQ Studio on your Q2.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Developer") {
                Person(login: Contributor.developer, name: "Surya JS", role: "This app: iPhone, iPad and Mac")
            }

            Section("Built On") {
                Person(login: "DiamondBond", name: "Bond", role: "EQ Studio and Q2 Pod: every feature here, and the icon")
                Person(login: "tyleree", name: "Tyler", role: "Q2 Theme Studio: the EQ engine this app runs")
            }

            Section {
                ContributorTicker(people: contributors.filter { !Contributor.named.contains($0.login.lowercased()) })
                    .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
            } header: {
                Text("Q2 Pod Contributors")
            } footer: {
                Text("Everyone else who has contributed to Q2 Pod on GitHub, the firmware EQ Studio runs on. Thank you.")
            }

            Section {
                ForEach(Acknowledgement.all) { a in
                    Link(destination: a.url) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(a.title).foregroundStyle(.primary).fontWeight(.medium)
                                Spacer()
                                Text(a.licence).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(a.detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                    }
                }
            } header: {
                Text("Acknowledgements")
            }
            .tint(.primary)

            Section {
                Link("GNU General Public License v3.0", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            } header: {
                Text("Licence")
            } footer: {
                Text("EQ Studio for Apple devices is free software under the GPL-3.0, as EQ Studio is. Not affiliated with Shanling.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
        .task { if let live = await Contributor.fetch() { contributors = live } }
    }
}

/// A person, by their GitHub picture and name, and what they did; a tap opens their profile.
private struct Person: View {
    let login: String
    var name: String?
    let role: String

    var body: some View {
        Link(destination: URL(string: "https://github.com/\(login)")!) {
            HStack(spacing: 12) {
                Avatar(login: login, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name ?? login).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        if name != nil { Text(login).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Text(role).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
        .accessibilityElement(children: .combine)
    }
}

private struct Avatar: View {
    let login: String
    let size: CGFloat
    var body: some View {
        AsyncImage(url: URL(string: "https://github.com/\(login).png?size=\(Int(size * 3))")) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.fill").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}

struct Acknowledgement: Identifiable {
    let title, detail, licence: String
    let url: URL
    var id: String { title }

    static let all: [Acknowledgement] = [
        .init(title: "EQ Studio", detail: "By Bond (DiamondBond). The Q2 Pod app this one talks to, every feature here, and the app's icon, which is EQ Studio's own.",
              licence: "GPL-3.0", url: URL(string: "https://github.com/DiamondBond/q2-eq-studio")!),
        .init(title: "Q2 Pod", detail: "By Bond and the Q2 Pod community. The firmware that plays the EQ live.",
              licence: "", url: URL(string: "https://github.com/DiamondBond/q2-pod")!),
        .init(title: "Q2 Theme Studio", detail: "By Tyler (tyleree). EQ Studio's EQ, and its logic ported here.",
              licence: "GPL-3.0", url: URL(string: "https://github.com/tyleree")!),
        .init(title: "AutoEq", detail: "By Jaakko Pasanen. The presets, from measurements by Crinacle, oratory1990 and others.",
              licence: "MIT", url: URL(string: "https://github.com/jaakkopasanen/AutoEq")!),
        .init(title: "PEQdB Studio", detail: "EQ Studio's computer layout and keys follow it.",
              licence: "", url: URL(string: "https://peqdb.com/studio")!),
        .init(title: "File Browser", detail: "By group-a-study. EQ Studio's Q2 glue and sign-in.",
              licence: "MIT", url: URL(string: "https://github.com/group-a-study/q2-filebrowser")!),
        .init(title: "squig.link", detail: "And its reviewers: the measurements and targets EQ Studio draws.",
              licence: "", url: URL(string: "https://squig.link")!),
    ]
}

struct Contributor: Identifiable, Codable, Sendable {
    let login: String
    var id: String { login }
    var profile: URL { URL(string: "https://github.com/\(login)")! }
    var avatar: URL { URL(string: "https://github.com/\(login).png?size=96")! }

    /// This app's developer, on GitHub.
    static let developer = "js-surya"
    /// Shown on their own above the rest: the developer, Bond and Tyler.
    static let named: Set<String> = ["js-surya", "diamondbond", "tyleree"]

    /// Q2 Pod's contributors when this was built, most contributions first.
    static let builtIn: [Contributor] = [
        "DiamondBond", "andsuor", "karanthakakr04", "tyleree", "claude", "lampsonlnguyen", "A4Link", "group-a-study",
        "tnt-accloo", "SlayTheEarth", "js-surya", "m-d-e-v", "polygonfuture", "hadad95", "genieoflamp", "jtliang24",
        "gukey", "0pac1ty", "harpmudd", "rafaelxaugusto", "czdaniel",
    ].map { Contributor(login: $0) }

    private static let keptKey = "q2pod-contributors"

    /// The list GitHub gave last time, else the one built in: what shows offline, and until GitHub answers.
    static var kept: [Contributor] {
        UserDefaults.standard.data(forKey: keptKey).flatMap { try? JSONDecoder().decode([Contributor].self, from: $0) } ?? builtIn
    }

    /// GitHub's list today: anyone who has joined since shows too. Kept for next time.
    static func fetch() async -> [Contributor]? {
        var all: [Contributor] = []
        for page in 1...5 {
            guard let url = URL(string: "https://api.github.com/repos/DiamondBond/q2-pod/contributors?per_page=100&page=\(page)") else { return nil }
            var r = URLRequest(url: url, timeoutInterval: 10)
            r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: r),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let list = try? JSONDecoder().decode([Contributor].self, from: data) else { return all.isEmpty ? nil : all }
            all += list
            if list.count < 100 { break }
        }
        if all.isEmpty { return nil }
        if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: keptKey) }
        return all
    }
}

/// Q2 Pod's other contributors by name, drifting right to left in a loop. A touch holds it, so a name can
/// be tapped (it opens their GitHub); with Reduce Motion it stands still, a row to swipe.
private struct ContributorTicker: View {
    let people: [Contributor]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0 // one copy of the row
    @State private var start = Date()
    @State private var held: Date?
    private let speed: CGFloat = 28 // points a second

    var body: some View {
        if reduceMotion || people.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) { row.padding(.horizontal, 16) }
        } else {
            TimelineView(.animation(paused: held != nil)) { context in
                let now = held ?? context.date
                let shift = width > 0 ? CGFloat(now.timeIntervalSince(start)) * speed : 0
                HStack(spacing: 0) {
                    row.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    row.accessibilityHidden(true)
                }
                .offset(x: width > 0 ? -shift.truncatingRemainder(dividingBy: width) : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                       .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if held == nil { held = Date() } }
                .onEnded { _ in
                    if let h = held { start = start.addingTimeInterval(Date().timeIntervalSince(h)) }
                    held = nil
                })
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(people) { c in
                Link(destination: c.profile) {
                    Text(c.login)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.fill.tertiary, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 8) // the gap before the loop starts again
        .fixedSize()
    }
}
