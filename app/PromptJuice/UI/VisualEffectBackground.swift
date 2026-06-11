import AppKit
import SwiftUI

/// Native vibrancy behind the Juicebar. `.hudWindow` keeps the panel dark and
/// vibrant in both light and dark menu bars, so the white panel content stays
/// legible while feeling first-party. This is the macOS 14 baseline; macOS 26
/// layers Liquid Glass on top via `liquidGlassPanel(in:)`.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

/// The panel's base material: system Liquid Glass on macOS 26+, and a vibrant
/// `NSVisualEffectView` on the macOS 14 baseline. A faint dark scrim keeps the
/// white panel content legible over bright desktops in both cases.
struct PanelMaterial: View {
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(Color.black.opacity(0.20))
                .glassEffect(.regular, in: shape)
        } else {
            ZStack {
                VisualEffectBackground()
                shape.fill(Color.black.opacity(0.24))
            }
            .clipShape(shape)
        }
    }
}
