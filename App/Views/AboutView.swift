// SPDX-License-Identifier: GPL-3.0-only
// Settings, and About: what this is, who made it, and everyone whose work it stands on.
import SwiftUI

/// Settings: the Q2 this device is signed in to, the look, the graph's extras, the keys, and About.
struct SettingsView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.dismiss) private var dismiss
    /// Opened from the EQ tab's gear: with a Done button.
    var sheet = false
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
            Section {
                ThemePicker()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Accent")
                        Spacer()
                        Text(studio.accentChoice.title).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 10)], spacing: 10) {
                        ForEach(AccentChoice.allCases) { choice in
                            let on = studio.accentChoice == choice
                            Button { withAnimation(.snappy) { studio.accentChoice = choice } } label: {
                                Circle()
                                    .fill(choice.color.gradient)
                                    .frame(width: 30, height: 30)
                                    .overlay { if on { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                                    .padding(3)
                                    .overlay { Circle().strokeBorder(on ? choice.color : .clear, lineWidth: 2) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Appearance")
            } footer: {
                Text("The accent colours the app and the graph's curve and dots. EQ Studio is the page's own blue; bands on the right side alone stay orange.")
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
                // Pushed from Settings itself, not by value: Settings is open through its gear's binding,
                // and a value pushed onto the tab's path would close it again.
                Button { showAbout = true } label: {
                    HStack {
                        Label("About EQ Studio", systemImage: "info.circle")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .tint(.primary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .toolbar {
            if sheet { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
        }
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

/// About: what this is, who made it, and whose work it stands on.
struct AboutView: View {
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
                    Text("A native app for EQ Studio, the Q2 Pod app by DiamondBond. It edits the same EQ, through EQ Studio on your Q2.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Developer") {
                Person(login: "js-surya", name: "Surya JS", role: "EQ Studio for iPhone and iPad")
            }

            Section("Built On") {
                Person(login: "DiamondBond", role: "EQ Studio · Q2 Pod")
                Person(login: "tyleree", role: "Q2 Theme Studio")
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
                Link("Source Code", destination: URL(string: "https://github.com/js-surya/q2-eq-studio-ios")!)
            } header: {
                Text("Licence")
            } footer: {
                Text("EQ Studio for iPhone and iPad is free software under the GPL-3.0, as EQ Studio is. Not affiliated with Shanling.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
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
        .init(title: "EQ Studio", detail: "By DiamondBond. The Q2 Pod app this one talks to, every feature here, and the app's icon, which is EQ Studio's own.",
              licence: "GPL-3.0", url: URL(string: "https://github.com/DiamondBond/q2-eq-studio")!),
        .init(title: "Q2 Pod", detail: "By DiamondBond and the Q2 Pod community. The firmware that plays the EQ live.",
              licence: "", url: URL(string: "https://github.com/DiamondBond/q2-pod")!),
        .init(title: "Q2 Theme Studio", detail: "By tyleree. EQ Studio's EQ, and its logic ported here.",
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


extension View {
    /// The gear at the top of a tab, on an iPhone and an iPad: Settings as a page of that tab, Back to it.
    /// The debug EQS_SETTINGS opens it.
    func settingsButton() -> some View { modifier(SettingsButton()) }
}

private struct SettingsButton: ViewModifier {
    @Environment(Studio.self) private var studio
    @State private var open = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { open = true }
                }
            }
            .navigationDestination(isPresented: $open) { SettingsView() }
            .onChange(of: studio.showSettings) { if studio.showSettings { open = true; studio.showSettings = false } }
            .onAppear { if studio.showSettings { open = true; studio.showSettings = false } }
    }
}
