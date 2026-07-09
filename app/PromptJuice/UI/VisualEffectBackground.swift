import SwiftUI

/// Dark scrim layered above the AppKit material root. AppKit owns the shaped
/// glass/vibrancy so the window server can trace the rounded panel outline.
struct PanelMaterial: View {
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            shape.fill(Color.black.opacity(0.20))
        } else {
            shape.fill(Color.black.opacity(0.24))
        }
    }
}
