// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A round or capsule glass button, tinted while it's on. The glass is drawn, not interactive: on iOS 26
/// a plain button under an interactive glass effect showed the glass's press but often never ran its
/// action (the pencil on the graph, a tester's iPad on 26.3), and only the icon itself took a tap. Here
/// the whole shape takes the tap, and a press scales it a little instead.
struct GlassButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(shape)
            .glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle<Circle> {
    static func glassCircle(tint: Color? = nil) -> Self { GlassButtonStyle(shape: Circle(), tint: tint) }
}

extension ButtonStyle where Self == GlassButtonStyle<Capsule> {
    static func glassCapsule(tint: Color? = nil) -> Self { GlassButtonStyle(shape: Capsule(), tint: tint) }
}
