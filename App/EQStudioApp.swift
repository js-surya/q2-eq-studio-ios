// SPDX-License-Identifier: GPL-3.0-only
// EQ Studio for iPhone, iPhone Duo, iPad and Mac: one SwiftUI app. Its tabs are a tab bar on an iPhone and
// a sidebar where there's room (an iPad, a Mac, an unfolded iPhone Duo), as the system lays them out.
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
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { studio.undo() }.keyboardShortcut("z").disabled(!studio.canUndo)
                Button("Redo") { studio.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!studio.canRedo)
                Button("Redo") { studio.redo() }.keyboardShortcut("y").disabled(!studio.canRedo)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy EQ as Text") { studio.copyEQ() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste EQ") {
                    if let t = Clipboard.text() { studio.open(text: String(t.prefix(Poweramp.fileMax)), name: "", from: "from the clipboard") }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save to the Card…") { studio.cardAsked = "save" }.keyboardShortcut("s")
            }
            CommandGroup(replacing: .newItem) {
                Button("Open File…") { studio.cardAsked = "open" }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard and Mouse") { studio.showKeys = true }.keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}

struct RootView: View {
    @Environment(Studio.self) private var studio
    @Environment(\.scenePhase) private var phase
    @State private var tab = Tab.eq
    @State private var showSignIn = false

    enum Tab: Hashable { case eq, presets, response, card, about }
    @AppStorage("eq-studio-theme") private var theme = "system"
    @FocusState private var keys: Bool

    var body: some View {
        Group {
            if studio.link == nil {
                ConnectView()
            } else {
                TabView(selection: $tab) {
                    SwiftUI.Tab("EQ", systemImage: "slider.vertical.3", value: Tab.eq) {
                        NavigationStack { EQView() }
                    }
                    SwiftUI.Tab("Presets", systemImage: "headphones", value: Tab.presets) {
                        NavigationStack { PresetsView() }
                    }
                    SwiftUI.Tab("Response", systemImage: "waveform.path.ecg", value: Tab.response) {
                        NavigationStack { ResponseView(goToEQ: { tab = .eq }) }
                    }
                    SwiftUI.Tab("Card", systemImage: "sdcard", value: Tab.card) {
                        NavigationStack { CardView() }
                    }
                    SwiftUI.Tab("About", systemImage: "info.circle", value: Tab.about) {
                        NavigationStack { AboutView() }
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
                        tab = [Tab.eq, .presets, .response, .card][i]
                    }
                    return handled ? .handled : .ignored
                }
                .onChange(of: studio.searchAsked) { if tab != .response { tab = .presets } }
                .onChange(of: studio.cardAsked) { if studio.cardAsked != nil { tab = .card } }
                .sheet(isPresented: Binding(get: { studio.showKeys }, set: { studio.showKeys = $0 })) { KeysSheet() }
                .onChange(of: phase) { if phase == .active { Task { await studio.readState() } } }
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
        .overlay(alignment: .bottom) { ToastView() }
        .alert(studio.notice?.title ?? "", isPresented: Binding(get: { studio.notice != nil }, set: { if !$0 { studio.notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(studio.notice?.text ?? "")
        }
        .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
    }
}

/// What the Q2 is doing with this EQ, under the tabs: live, sending, an editor only, or what went wrong.
struct LiveStatus: View {
    @Environment(Studio.self) private var studio
    let signIn: () -> Void

    var body: some View {
        let live = studio.live
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
    /// Under the tabs on an iPhone and an iPad, the bar's own accessory; at the window's foot on a Mac.
    @ViewBuilder func liveStatus(@ViewBuilder _ status: () -> some View) -> some View {
        #if os(iOS)
        tabViewBottomAccessory { status() }
        #else
        let s = status()
        safeAreaInset(edge: .bottom) {
            s.padding(.vertical, 8).frame(maxWidth: 560).glassEffect(.regular, in: .capsule).padding(.bottom, 10)
        }
        #endif
    }

    /// Settings' look: inset grouped on an iPhone and an iPad, the Mac's own inset list.
    @ViewBuilder func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
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
            .padding(.bottom, 110)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
