// SPDX-License-Identifier: GPL-3.0-only
// EQ Studio for iPhone, iPhone Duo and iPad: one SwiftUI app. Its tabs are a tab bar on an iPhone and a
// sidebar where there's room (an iPad, an unfolded iPhone Duo), as the system lays them out.
import EQCore
import SwiftUI

@main
struct EQStudioApp: App {
    @State private var studio = Studio()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(studio)
        }
    }
}

struct RootView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.scenePhase) private var phase
    @State private var tab: Tab = {
        #if DEBUG
        // For screenshots on a simulator: EQS_TAB=presets (response, card, about) opens on that tab.
        switch ProcessInfo.processInfo.environment["EQS_TAB"] {
        case "presets": return .search
        case "response": return .response
        case "card": return .card
        case "search": return .search
        default: break
        }
        #endif
        return .eq
    }()
    @State private var showSignIn = false

    enum Tab: Hashable { case eq, response, card, search }
    @AppStorage("eq-studio-theme") private var theme = "system"
    @FocusState private var keys: Bool

    var body: some View {
        Group {
            if studio.link == nil && !studio.trying {
                ConnectView()
            } else {
                TabView(selection: $tab) {
                    SwiftUI.Tab("EQ", systemImage: "slider.vertical.3", value: Tab.eq) {
                        NavigationStack { EQView() }
                    }
                    SwiftUI.Tab("Response", systemImage: "waveform.path.ecg", value: Tab.response) {
                        NavigationStack { ResponseView(goToEQ: { tab = .eq }) }
                    }
                    SwiftUI.Tab("Card", systemImage: "sdcard", value: Tab.card) {
                        NavigationStack { CardView() }
                    }
                    // Presets in the bar's own slot at the right, which stays there as the bar collapses.
                    SwiftUI.Tab("Presets", systemImage: "headphones", value: Tab.search, role: .search) {
                        NavigationStack { SearchView(goToEQ: { tab = .eq }) }
                    }

                }
                .tabViewStyle(.sidebarAdaptable)
                .liveStatus { LiveStatus(signIn: { showSignIn = true }) }
                .task { await studio.readState(first: true) }
                .task { if let note = await studio.response.restore() { studio.say(note) } }
                .focusable()
                .focusEffectDisabled()
                .focused($keys)
                .defaultFocus($keys, true)
                .onKeyPress(phases: [.down, .repeat]) { press in
                    if press.modifiers.contains(.command) || press.modifiers.contains(.control) || press.modifiers.contains(.option) { return .ignored }
                    let name: String
                    switch press.key {
                    case .leftArrow: name = "left"
                    case .rightArrow: name = "right"
                    case .upArrow: name = "up"
                    case .downArrow: name = "down"
                    case .delete, .deleteForward: name = "delete"
                    case .escape: name = "escape"
                    case .space: name = " "
                    default: name = press.characters.lowercased()
                    }
                    let handled = studio.key(name, shift: press.modifiers.contains(.shift), again: press.phase == .repeat) { i in
                        tab = [Tab.eq, .search, .response, .card][i]
                    }
                    return handled ? .handled : .ignored
                }
                .onChange(of: studio.searchAsked) { if studio.searchAsked != nil && tab != .response { tab = .search } }
                .onChange(of: studio.cardAsked) { if studio.cardAsked != nil { tab = .card } }
                // Presets opens with the cursor in its search box.
                .onChange(of: tab) { if tab == .search { studio.searchAsked = UUID() } }
                .onAppear { if tab == .search { studio.searchAsked = UUID() } }
                #if DEBUG
                .onAppear { if ProcessInfo.processInfo.environment["EQS_SETTINGS"] != nil { studio.showSettings = true } }
                .task { if ProcessInfo.processInfo.environment["EQS_TOAST"] != nil { try? await Task.sleep(for: .seconds(2)); studio.say("“Meze Alba” is playing.", undo: true) } }
                #endif
                .sheet(isPresented: Binding(get: { studio.showKeys }, set: { studio.showKeys = $0 })) { KeysSheet() }
                .sheet(isPresented: Binding(get: { studio.pasteAsked }, set: { studio.pasteAsked = $0 })) { PasteSheet() }

                .onChange(of: phase) {
                    if phase == .active { Task { await studio.readState() } } else { studio.storeNow() }
                }
                .sheet(isPresented: $showSignIn) { SignInForm() }
                .dropDestination(for: URL.self) { urls, _ in
                    // A preset's file dropped on the window opens, as on the page.
                    guard let url = urls.first else { return false }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { return false }
                    guard data.count <= Poweramp.fileMax else {
                        studio.tell("This preset couldn't be opened", "It's too big to be a preset.")
                        return true
                    }
                    let name = url.lastPathComponent.replacingOccurrences(of: #"\.json$"#, with: "", options: [.regularExpression, .caseInsensitive])
                    studio.open(text: String(decoding: data, as: UTF8.self), name: nameOfFile(name), from: "from the file")
                    return true
                }
            }
        }
        .overlay(alignment: .top) { ToastView() }
        .alert(studio.notice?.title ?? "", isPresented: Binding(get: { studio.notice != nil }, set: { if !$0 { studio.notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(studio.notice?.text ?? "")
        }
        .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
        .tint(studio.accent)
        .sensoryFeedback(trigger: studio.haptic) { _, event in event?.kind.feedback }
    }
}

/// What the Q2 is doing with this EQ, under the tabs: live, sending, an editor only, or what went wrong.
struct LiveStatus: View {
    @Environment(Studio.self) private var studio
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let signIn: () -> Void

    /// Beside the tab bar once it has collapsed: one short line.
    private var inline: Bool {
        placement == .inline
    }

    var body: some View {
        let live = studio.live
        if inline { compact(live) } else { full(live) }
    }

    private func compact(_ live: Studio.LiveState) -> some View {
        HStack(spacing: 8) {
            if live.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Can't reach the Q2").font(.footnote.weight(.medium)).lineLimit(1)
            } else if studio.link == nil {
                Image(systemName: "hifispeaker.slash").foregroundStyle(.secondary)
                Text("No Q2 connected").font(.footnote.weight(.medium)).lineLimit(1)
            } else if !live.known {
                ProgressView().controlSize(.small)
                Text("Reaching the Q2…").font(.footnote).lineLimit(1)
            } else if live.local {
                Image(systemName: "pencil.and.list.clipboard").foregroundStyle(.secondary)
                Text("Editor only").font(.footnote.weight(.medium)).lineLimit(1)
            } else {
                Circle()
                    .fill(live.mode == "peq" ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(live.sending ? "Sending…" : live.mode == "peq" ? "Playing on the Q2" : "EQ off").font(.footnote.weight(.medium)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    private func full(_ live: Studio.LiveState) -> some View {
        HStack(spacing: 10) {
            if let error = live.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).font(.footnote).lineLimit(2)
                Spacer(minLength: 4)
                if error == Q2Error.signIn.localizedDescription {
                    Button("Sign In", action: signIn).buttonStyle(.glass)
                } else if let retry = live.retry {
                    Button("Retry") { retry() }.buttonStyle(.glass)
                }
            } else if studio.link == nil {
                Image(systemName: "hifispeaker.slash").foregroundStyle(.secondary)
                Text("No Q2 connected: the EQ stays on this device").font(.footnote).lineLimit(2)
                Spacer(minLength: 4)
                Button("Connect") { studio.trying = false }.buttonStyle(.glass)
            } else if !live.known {
                ProgressView().controlSize(.small)
                Text("Reaching the Q2…").font(.footnote)
                Spacer()
            } else if live.local {
                Image(systemName: "pencil.and.list.clipboard").foregroundStyle(.secondary)
                Text("Editor only: save to the card, then import on the Q2").font(.footnote).lineLimit(2)
                Spacer()
            } else {
                Circle()
                    .fill(live.mode == "peq" ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                    .symbolEffect(.pulse, isActive: live.sending)
                Text(live.sending ? "Sending to the Q2…" : live.mode == "peq" ? "Playing on the Q2" : "EQ off on the Q2")
                    .font(.footnote.weight(.medium))
                Spacer()
                if let link = studio.link { Text(link.address).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
        }
        .padding(.horizontal, 16)
        .animation(.default, value: live.sending)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Under the tabs: the bar's own accessory.
    @ViewBuilder func liveStatus(@ViewBuilder _ status: () -> some View) -> some View {
        // On an iPhone the tab bar collapses as the page scrolls down, the status beside it, and comes back up.
        tabViewBottomAccessory { status() }
            .tabBarMinimizeBehavior(.onScrollDown)
    }

    /// Settings' look: inset grouped.
    @ViewBuilder func groupedList() -> some View {
        listStyle(.insetGrouped)
    }
}

/// The toast: a line saying what happened, with Undo after a preset loads.
struct ToastView: View {
    @Environment(Studio.self) private var studio

    var body: some View {
        if let t = studio.toast {
            HStack(spacing: 12) {
                Text(t.text).font(.subheadline).lineLimit(3)
                if t.undo {
                    Button("Undo") {
                        studio.undo()
                        studio.toast = nil
                    }
                    .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 20)
            .padding(.top, 60) // under the bar's buttons, over the title for its few seconds
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(t.id)
            .onTapGesture { studio.toast = nil }
        }
    }
}

/// Light, dark or the system's, as the page's theme button picks.
struct ThemePicker: View {
    @AppStorage("eq-studio-theme") private var theme = "system"
    var body: some View {
        Picker("Theme", selection: $theme) {
            Label("System", systemImage: "circle.lefthalf.filled").tag("system")
            Label("Light", systemImage: "sun.max").tag("light")
            Label("Dark", systemImage: "moon").tag("dark")
        }
    }
}

