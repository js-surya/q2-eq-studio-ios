// SPDX-License-Identifier: GPL-3.0-only
import EQCore
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

/// Each band's colour on the graph and in the list, around the wheel.
enum BandColor {
    private static let hues: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .red, .indigo, .mint, .cyan, .brown]
    static func of(_ index: Int) -> Color { hues[index % hues.count] }
}
