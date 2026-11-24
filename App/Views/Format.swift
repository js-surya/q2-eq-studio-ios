// SPDX-License-Identifier: GPL-3.0-only
import EQCore
import GameController
import SwiftUI

enum Format {
    /// 31 Hz, 250 Hz, 1 kHz, 1.2 kHz, 16 kHz.
    static func hertz(_ f: Double) -> String {
        if f >= 1000 {
            let k = f / 1000
            return (k >= 10 ? String(format: "%.1f", k) : String(format: "%.2f", k))
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) + " kHz"
        }
        return String(format: f < 100 ? "%.1f" : "%.0f", f).replacingOccurrences(of: #"\.0$"#, with: "", options: .regularExpression) + " Hz"
    }

    static func gridHertz(_ f: Double) -> String { f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))" }

    static func dB(_ v: Double, digits: Int = 1) -> String {
        let s = String(format: "%.\(digits)f", abs(v) < 0.05 ? 0 : v)
        return (v >= 0.05 ? "+" : "") + s.replacingOccurrences(of: "-", with: "−") + " dB"
    }

    static func q(_ v: Double) -> String { "Q " + decimal(v, 2) }

    static func typeName(_ t: FilterType) -> String {
        switch t {
        case .peak: "Peak"
        case .lowShelf: "Low Shelf"
        case .highShelf: "High Shelf"
        }
    }

    static func typeShort(_ t: FilterType) -> String {
        switch t {
        case .peak: "PK"
        case .lowShelf: "LS"
        case .highShelf: "HS"
        }
    }

    static func channelName(_ c: Channel) -> String {
        switch c {
        case .all: "Both"
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// A band's colour, as the page has it (web/style.css, light and dark): the accent, orange for the right
/// side alone, faint when off; the picked dot filled with the accent's fill.
enum BandColor {
    /// The graph's colour: the app's accent (Color.accentColor follows the chosen one), which with EQ Studio
    /// chosen is EQ Studio's blue.
    static let accent = Color.accentColor
    /// EQ Studio's own blue, by name, whatever accent is chosen.
    static let studio = Color("AccentColor")
    /// The chosen accent, set by Studio: EQ Studio's gives the picked dot the page's own fill, Orange's
    /// clashes with the right side's orange (blue then), Graphite's with off bands' grey (fainter then).
    nonisolated(unsafe) static var choice = AccentChoice.studio
    static var right: Color { choice == .orange ? studio : Color("RightSide") }
    static var faint: Color { choice == .graphite ? Color("Faint").opacity(0.45) : Color("Faint") }
    static let fill = Color("AccentFill")
    static func of(_ band: Band) -> Color { !band.on ? faint : band.channel == .right ? right : accent }
    static func picked(_ band: Band) -> Color { !band.on ? faint : band.channel == .right ? right : choice == .studio ? fill : accent }
}

/// What this device is: keys and a pointer are an iPad's, not a phone's.
enum Device {
    /// An iPad with a mouse or trackpad, now: what Inspect's line follows without a touch. A finger reads the
    /// curve by touching and holding, so without one Inspect has nothing to add. Never an iPhone, which can
    /// report a pointer too (iPhone Mirroring from a Mac).
    @MainActor static var hasPointer: Bool { isPad && Peripherals.shared.mouse }
    /// An iPad with a keyboard or a mouse, now: what the Keyboard and Mouse sheet is about.
    @MainActor static var hasKeyboard: Bool { isPad && (Peripherals.shared.keyboard || Peripherals.shared.mouse) }
    @MainActor private static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

/// Which keyboards and mice are connected, kept up to date as they come and go, so the views showing
/// Inspect and the keys redraw with them.
@MainActor @Observable final class Peripherals {
    static let shared = Peripherals()
    private(set) var mouse = false
    private(set) var keyboard = false

    private init() {
        update()
        let names: [Notification.Name] = [.GCMouseDidConnect, .GCMouseDidDisconnect, .GCKeyboardDidConnect, .GCKeyboardDidDisconnect]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in Peripherals.shared.update() }
            }
        }
    }

    private func update() {
        let m = !GCMouse.mice().isEmpty, k = GCKeyboard.coalesced != nil
        if mouse != m { mouse = m }
        if keyboard != k { keyboard = k }
    }
}

/// The app's haptics, as Apple's patterns name them.
enum Haptic {
    case tick // a step: a whole dB, a grid frequency, a width step
    case bump // a landmark: 0 dB, a slider's centre
    case limit // as far as it goes
    case light // a pick, a toggle, undo
    case add, remove
    case success, failure

    var feedback: SensoryFeedback {
        switch self {
        case .tick: .selection
        case .bump: .impact(weight: .medium, intensity: 0.8)
        case .limit: .impact(flexibility: .rigid, intensity: 1)
        case .light: .impact(weight: .light, intensity: 0.7)
        case .add: .impact(weight: .medium)
        case .remove: .impact(weight: .heavy, intensity: 0.8)
        case .success: .success
        case .failure: .error
        }
    }
}

struct HapticEvent: Equatable {
    let id = UUID()
    let kind: Haptic
}

/// The app's accent choices: EQ Studio's blue first, then iOS's own colours.
enum AccentChoice: String, CaseIterable, Identifiable {
    case studio, lively, indigo, purple, pink, red, orange, yellow, green, mint, teal, graphite
    var id: String { rawValue }
    var title: String { self == .studio ? "EQ Studio" : rawValue.capitalized }
    var color: Color {
        switch self {
        case .studio: BandColor.studio
        case .lively: Color(red: 0x1D / 255, green: 0xB9 / 255, blue: 0x54 / 255) // a bright green, #1DB954
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .graphite: .gray
        }
    }
}
