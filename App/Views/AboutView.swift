// SPDX-License-Identifier: GPL-3.0-only
// About: what this is, the Q2 it's signed in to, everyone whose work it stands on, and every
// contributor to Q2 Pod by their GitHub name, read from GitHub (the list built in when offline).
import SwiftUI

struct AboutView: View {
    @Environment(Studio.self) private var studio
    @State private var contributors: [Contributor] = Contributor.builtIn
    @State private var confirmDisconnect = false

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

            if let link = studio.link {
                Section("Q2") {
                    LabeledContent("Address", value: link.address)
                    LabeledContent("Live EQ", value: studio.live.local ? "Not on this Q2 Pod" : studio.live.on ? "On" : "—")
                    Button("Sign Out", role: .destructive) { confirmDisconnect = true }
                }
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

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 16) {
                    ForEach(contributors) { c in
                        Link(destination: c.profile) {
                            VStack(spacing: 6) {
                                AsyncImage(url: c.avatar) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "person.fill").foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(.quaternary)
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(.circle)
                                Text(c.login)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(c.login)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Q2 Pod Contributors")
            } footer: {
                Text("Everyone who has contributed to Q2 Pod on GitHub, the firmware EQ Studio runs on. Thank you.")
            }

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
        .confirmationDialog("Sign out of this Q2?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { studio.disconnect() }
        } message: {
            Text("To come back, scan the Q2's code again.")
        }
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

struct Contributor: Identifiable, Decodable, Sendable {
    let login: String
    var id: String { login }
    var profile: URL { URL(string: "https://github.com/\(login)")! }
    var avatar: URL { URL(string: "https://github.com/\(login).png?size=96")! }

    /// Q2 Pod's contributors when this was built, most contributions first.
    static let builtIn: [Contributor] = [
        "DiamondBond", "andsuor", "karanthakakr04", "tyleree", "claude", "lampsonlnguyen", "A4Link", "group-a-study",
        "tnt-accloo", "SlayTheEarth", "js-surya", "m-d-e-v", "polygonfuture", "hadad95", "genieoflamp", "jtliang24",
        "gukey", "0pac1ty", "harpmudd", "rafaelxaugusto", "czdaniel",
    ].map { Contributor(login: $0) }

    /// GitHub's list today: anyone who has joined since shows too.
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
        return all.isEmpty ? nil : all
    }
}
