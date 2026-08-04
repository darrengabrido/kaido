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
enum BikePuckImage {
    static let bearing: UIImage? = makeBearingImage()

    /// Sonar-style pulse ring around the puck. Mapbox animates this natively — this only
    /// recolors and resizes it to match the accent used everywhere else on the map.
    static var pulsing: Puck2DConfiguration.Pulsing {
        Puck2DConfiguration.Pulsing(color: UIColor(Color.kaidoVioletOnMap), radius: .constant(26))
    }

    private static func makeBearingImage() -> UIImage? {
        let violetOnMap = UIColor(Color.kaidoVioletOnMap)
        let midnight = UIColor(Color.kaidoMidnight)
        let bmxYellow = UIColor(red: 0xF3 / 255, green: 0xB2 / 255, blue: 0x3A / 255, alpha: 1)
        let chrome = UIColor(red: 0xD7 / 255, green: 0xDB / 255, blue: 0xE2 / 255, alpha: 1)
        let tireDark = UIColor(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1B / 255, alpha: 1)

        let size = CGSize(width: 72, height: 72)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let discRadius: CGFloat = 15

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

            drawBmxGlyph(in: cg, center: center, bmxYellow: bmxYellow, chrome: chrome, tireDark: tireDark)
        }
    }

    /// A cone that's brightest near the puck and fades to nothing at its tip — reads as "this
    /// way" once the puck is rotated to match the rider's course.
    private static func drawHeadingWedge(in cg: CGContext, center: CGPoint, discRadius: CGFloat, color: UIColor) {
        let tip = CGPoint(x: center.x, y: center.y - discRadius - 22)
        let baseHalfWidth: CGFloat = 12
        let baseY = center.y - discRadius + 4

        let wedge = CGMutablePath()
        wedge.move(to: tip)
        wedge.addLine(to: CGPoint(x: center.x - baseHalfWidth, y: baseY))
        wedge.addQuadCurve(
            to: CGPoint(x: center.x + baseHalfWidth, y: baseY),
            control: CGPoint(x: center.x, y: baseY + 6)
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

    /// A side-view BMX in miniature: two wheels, a diamond frame, cockpit, seat, and chainring —
    /// styled after a real childhood bike rather than a generic bicycle icon.
    private static func drawBmxGlyph(
        in cg: CGContext,
        center: CGPoint,
        bmxYellow: UIColor,
        chrome: UIColor,
        tireDark: UIColor
    ) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x, y: center.y + y)
        }

        let wheelRadius: CGFloat = 4.7
        let rimRadius: CGFloat = 3.25
        let rear = point(-7.8, 3.6)
        let front = point(7.8, 3.6)
        let bottomBracket = point(-0.65, 4.2)
        let headTop = point(6.8, -4.4)
        let seatTop = point(-6.0, -4.7)
        let barLeft = point(2.9, -7.0)
        let barRight = point(10.7, -7.0)
        let barCenter = CGPoint(x: (barLeft.x + barRight.x) / 2, y: barLeft.y)

        cg.setStrokeColor(tireDark.cgColor)
        cg.setLineWidth(2.6)
        for hub in [rear, front] {
            cg.addEllipse(in: CGRect(
                x: hub.x - wheelRadius, y: hub.y - wheelRadius,
                width: wheelRadius * 2, height: wheelRadius * 2
            ))
        }
        cg.strokePath()

        cg.setFillColor(chrome.cgColor)
        for hub in [rear, front] {
            cg.addEllipse(in: CGRect(
                x: hub.x - rimRadius, y: hub.y - rimRadius,
                width: rimRadius * 2, height: rimRadius * 2
            ))
        }
        cg.fillPath()

        let frame = CGMutablePath()
        frame.move(to: seatTop); frame.addLine(to: headTop) // top tube
        frame.move(to: headTop); frame.addLine(to: bottomBracket) // down tube
        frame.move(to: seatTop); frame.addLine(to: bottomBracket) // seat tube
        frame.move(to: bottomBracket); frame.addLine(to: rear) // chain stay
        frame.move(to: seatTop); frame.addLine(to: rear) // seat stay
        cg.setStrokeColor(bmxYellow.cgColor)
        cg.setLineWidth(2.2)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.addPath(frame)
        cg.strokePath()

        let cockpit = CGMutablePath()
        cockpit.move(to: headTop); cockpit.addLine(to: front) // fork
        cockpit.move(to: headTop); cockpit.addLine(to: barCenter) // stem
        cockpit.move(to: barLeft); cockpit.addLine(to: barRight) // handlebar
        cg.setStrokeColor(chrome.cgColor)
        cg.setLineWidth(1.8)
        cg.addPath(cockpit)
        cg.strokePath()

        cg.setStrokeColor(tireDark.cgColor)
        cg.setLineWidth(3)
        cg.setLineCap(.round)
        cg.move(to: CGPoint(x: seatTop.x - 1.6, y: seatTop.y))
        cg.addLine(to: CGPoint(x: seatTop.x + 1.6, y: seatTop.y))
        cg.strokePath()

        cg.setFillColor(chrome.cgColor)
        cg.addEllipse(in: CGRect(
            x: bottomBracket.x - 1.6, y: bottomBracket.y - 1.6,
            width: 3.2, height: 3.2
        ))
        cg.fillPath()
    }
}
