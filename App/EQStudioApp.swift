// SPDX-License-Identifier: GPL-3.0-only
// EQ Studio for iPhone, iPhone Duo, iPad and Mac: one SwiftUI app. Its tabs are a tab bar on an iPhone and
// a sidebar where there's room (an iPad, a Mac, an unfolded iPhone Duo), as the system lays them out.
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

    enum Tab: Hashable { case eq, presets, card, about }

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
                .onChange(of: phase) { if phase == .active { Task { await studio.readState() } } }
                .sheet(isPresented: $showSignIn) { SignInForm() }
            }
        }
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
