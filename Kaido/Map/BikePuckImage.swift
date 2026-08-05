import MapboxMaps
import SwiftUI
import UIKit

/// The rider's live-position marker — a forward-pointing heading wedge behind a violet-ringed
/// disc holding a small BMX glyph, an ode to a childhood bike. Shared by every map that shows
/// the puck (browsing, route preview, and turn-by-turn) so "you" looks the same everywhere.
///
/// Mapbox rotates `bearingImage` as a single unit, so the wedge and the glyph turn together —
/// there's no native way to keep the glyph upright while only the wedge rotates without dropping
/// the built-in puck for a hand-built annotation (losing its GPS smoothing and accuracy handling
/// in the process). One rotating image is the same tradeoff the previous bicycle glyph already
/// made, so this isn't a new limitation.
///
/// The glyph is a bold single-tone silhouette, not delicate multi-part line art — a real puck on
/// a phone screen renders at a few dozen points, and thin multi-color strokes that read fine in
/// a large preview mockup blur into a smudge at that size. Bold shapes survive the trip down.
enum BikePuckImage {
    static let bearing: UIImage? = makeBearingImage()

    /// Sonar-style pulse ring around the puck. Mapbox animates this natively — this only
    /// recolors and resizes it to match the accent used everywhere else on the map.
    static var pulsing: Puck2DConfiguration.Pulsing {
        Puck2DConfiguration.Pulsing(color: UIColor(Color.kaidoVioletOnMap), radius: .constant(22))
    }

    private static func makeBearingImage() -> UIImage? {
        let violetOnMap = UIColor(Color.kaidoVioletOnMap)
        let midnight = UIColor(Color.kaidoMidnight)
        let bmxYellow = UIColor(red: 0xF3 / 255, green: 0xB2 / 255, blue: 0x3A / 255, alpha: 1)

        let size = CGSize(width: 56, height: 56)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let discRadius: CGFloat = 12

        return renderer.image { context in
            let cg = context.cgContext

            drawHeadingWedge(in: cg, center: center, discRadius: discRadius, color: violetOnMap)

            let discRect = CGRect(
                x: center.x - discRadius,
                y: center.y - discRadius,
                width: discRadius * 2,
                height: discRadius * 2
            )
            cg.setFillColor(midnight.cgColor)
            cg.setStrokeColor(violetOnMap.cgColor)
            cg.setLineWidth(2)
            cg.addEllipse(in: discRect)
            cg.drawPath(using: .fillStroke)

            drawBmxGlyph(in: cg, center: center, color: bmxYellow)
        }
    }

    /// A cone that's brightest near the puck and fades to nothing at its tip — reads as "this
    /// way" once the puck is rotated to match the rider's course. Kept fully inside the canvas
    /// (tip margin below `center.y - size/2`) so the point never clips off.
    private static func drawHeadingWedge(in cg: CGContext, center: CGPoint, discRadius: CGFloat, color: UIColor) {
        let tip = CGPoint(x: center.x, y: center.y - discRadius - 11)
        let baseHalfWidth: CGFloat = 8
        let baseY = center.y - discRadius + 2

        let wedge = CGMutablePath()
        wedge.move(to: tip)
        wedge.addLine(to: CGPoint(x: center.x - baseHalfWidth, y: baseY))
        wedge.addQuadCurve(
            to: CGPoint(x: center.x + baseHalfWidth, y: baseY),
            control: CGPoint(x: center.x, y: baseY + 5)
        )
        wedge.closeSubpath()

        cg.saveGState()
        cg.addPath(wedge)
        cg.clip()

        let colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: center.x, y: baseY),
                end: CGPoint(x: center.x, y: tip.y),
                options: []
            )
        }
        cg.restoreGState()
    }

    /// A side-view BMX reduced to its essential silhouette: two bold wheel rings, a solid frame
    /// triangle, and single strokes for the stays, fork, bar, and seat — one tone throughout.
    private static func drawBmxGlyph(in cg: CGContext, center: CGPoint, color: UIColor) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x, y: center.y + y)
        }

        let wheelRadius: CGFloat = 4.2
        let rear = point(-6.2, 2.6)
        let front = point(6.2, 2.6)
        let bottomBracket = point(0, 2.8)
        let headTop = point(4.6, -3.2)
        let seatTop = point(-4.6, -3.0)

        cg.setStrokeColor(color.cgColor)
        cg.setFillColor(color.cgColor)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        cg.setLineWidth(2.6)
        for hub in [rear, front] {
            cg.addEllipse(in: CGRect(
                x: hub.x - wheelRadius, y: hub.y - wheelRadius,
                width: wheelRadius * 2, height: wheelRadius * 2
            ))
        }
        cg.strokePath()

        let frame = CGMutablePath()
        frame.move(to: seatTop)
        frame.addLine(to: headTop)
        frame.addLine(to: bottomBracket)
        frame.closeSubpath()
        cg.addPath(frame)
        cg.fillPath()

        let stays = CGMutablePath()
        stays.move(to: bottomBracket); stays.addLine(to: rear) // chain stay
        stays.move(to: seatTop); stays.addLine(to: rear) // seat stay
        stays.move(to: headTop); stays.addLine(to: front) // fork
        cg.setLineWidth(2.4)
        cg.addPath(stays)
        cg.strokePath()

        let cockpit = CGMutablePath()
        cockpit.move(to: CGPoint(x: headTop.x - 2.2, y: headTop.y - 2.6))
        cockpit.addLine(to: CGPoint(x: headTop.x + 2.6, y: headTop.y - 2.6)) // handlebar
        cockpit.move(to: headTop)
        cockpit.addLine(to: CGPoint(x: headTop.x, y: headTop.y - 2.6)) // stem
        cg.setLineWidth(2.6)
        cg.addPath(cockpit)
        cg.strokePath()

        cg.setLineWidth(3)
        cg.move(to: CGPoint(x: seatTop.x - 1.6, y: seatTop.y - 1.4))
        cg.addLine(to: CGPoint(x: seatTop.x + 1.2, y: seatTop.y - 1.4)) // seat
        cg.strokePath()
    }
}
