import SwiftUI

/// The teardrop silhouette, traced from the shared `DropletGeometry`.
struct DropletShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: DropletGeometry.point(DropletGeometry.tip, in: rect))

        for segment in DropletGeometry.segments {
            path.addCurve(
                to: DropletGeometry.point(segment.2, in: rect),
                control1: DropletGeometry.point(segment.0, in: rect),
                control2: DropletGeometry.point(segment.1, in: rect)
            )
        }

        path.closeSubpath()
        return path
    }
}

/// A droplet whose juice fill level encodes remaining capacity. Full renders as
/// a solid drop (the classic `drop.fill`); as capacity drains a waterline
/// appears and recedes; near empty the juice pools into a last-drop bead.
struct DropletGauge: View {
    /// Remaining capacity, 0...1.
    var remaining: Double
    var tint: Color
    var lineWidth: CGFloat = 1.8

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)

            ZStack {
                juice(in: rect)

                DropletShape()
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            }
        }
    }

    @ViewBuilder
    private func juice(in rect: CGRect) -> some View {
        if remaining >= DropletGeometry.solidFillThreshold {
            DropletShape().fill(tint)
        } else if remaining > 0 {
            wave(in: rect)
                .fill(tint)
                .clipShape(DropletShape())
        }
    }

    private func wave(in rect: CGRect) -> Path {
        let y = DropletGeometry.waterline(forRemaining: remaining) * rect.height
        let amplitude = rect.height * 0.02

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: y),
            control: CGPoint(x: rect.width * 0.25, y: y - amplitude)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: y),
            control: CGPoint(x: rect.width * 0.75, y: y + amplitude)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
