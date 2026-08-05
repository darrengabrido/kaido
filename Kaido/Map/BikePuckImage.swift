import MapboxMaps
import SwiftUI
import UIKit

/// The rider's live-position marker — the BMX itself, no badge or disc around it, with a heading
/// wedge sweeping behind it. Shared by every map that shows the puck (browsing, route preview,
/// and turn-by-turn) so "you" looks the same everywhere.
///
/// Mapbox's 2D puck stacks two images on the location point, and the split matters:
///
///   `bearingImage` rotates with the rider's course — so only the wedge lives there.
///   `topImage` never rotates — so the bike lives there, and stays upright at every heading.
///
/// Putting the bike in `bearingImage` would flip it upside down on any southward heading, and
/// leaving `topImage` unset is worse still: it does not fall back to nothing, it falls back to
/// Mapbox's default blue dot, which then draws over the bike and hides it.
enum BikePuckImage {
    /// Rotates with course. Deliberately a larger canvas than `top` so the wedge can extend
    /// well past the bike — both images are centred on the same location point.
    static let bearing: UIImage? = makeBearingImage()

    /// Always upright, drawn above `bearing`.
    static let top: UIImage? = makeTopImage()

    /// Sonar-style pulse ring around the puck. Mapbox animates this natively — this only
    /// recolors and resizes it to match the accent used everywhere else on the map.
    ///
    /// The radius has to clear the glyph or the pulse never reads as expanding outward. The
    /// bike is ~40pt wide, so this keeps roughly the same ring-to-glyph ratio it had at the
    /// previous smaller size.
    static var pulsing: Puck2DConfiguration.Pulsing {
        Puck2DConfiguration.Pulsing(color: UIColor(Color.kaidoVioletOnMap), radius: .constant(30))
    }

    // The bike's body carries the palette's hero neutral — the same warm off-white as speed,
    // time, and street names, so "you" reads with the weight of the most important data on
    // screen. It deliberately isn't the bike's real-world yellow: amber already means caution
    // in this app (`statusCaution` flags low battery and a dropped Ride Together connection),
    // and a second accent outside the violet system would be the only one on the map that
    // means nothing. The tribute lives in the shape, not the hex.
    private static let frameColor = UIColor(Color.kaidoInk)

    /// Fork, bars, hubs, cranks — violet, so the puck stays inside the one-accent system.
    /// Violet can't carry the whole bike: on top of its own violet route the glyph disappears.
    private static let hardwareColor = UIColor(Color.kaidoVioletOnMap)

    /// Rubber — a thin dark edge outside the rim. Near-black rather than pure, matching the
    /// palette's rule that the ground is warm near-black and never #000.
    private static let rubber = UIColor(red: 0x15 / 255, green: 0x15 / 255, blue: 0x1A / 255, alpha: 1)

    /// Scales the bike's base geometry (drawn in ~24pt-wide units) up to ~40pt on screen.
    ///
    /// Dimensionality needs pixels to live in: at the previous ~31pt the contact shadow and tyre
    /// edge just read as noise. Waze's marker — the reference for this pass — is roughly twice
    /// that again, which is most of why theirs reads as an object and a small flat icon can't.
    private static let glyphScale: CGFloat = 1.65

    /// The wedge is sized on its own scale rather than tracking `glyphScale`. Its job is to say
    /// "this way" without pulling focus, and matching the bike's full scale made it a violet
    /// triangle that dominated the bike it was meant to support.
    private static let wedgeScale: CGFloat = 1.45

    private static func renderer(_ side: CGFloat) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    }

    /// A cone that's brightest at the puck and fades to nothing at its tip — reads as "this way"
    /// once Mapbox rotates it to the rider's course.
    private static func makeBearingImage() -> UIImage? {
        // The canvas has to clear the wedge tip, which reaches ~27pt above centre.
        let side: CGFloat = 72
        let center = CGPoint(x: side / 2, y: side / 2)
        let violet = UIColor(Color.kaidoVioletOnMap)
        let k = wedgeScale

        return renderer(side).image { context in
            let cg = context.cgContext

            let tip = CGPoint(x: center.x, y: center.y - 18.75 * k)
            let baseY = center.y - 6.25 * k
            let baseHalfWidth = 7.03 * k

            let wedge = CGMutablePath()
            wedge.move(to: tip)
            wedge.addLine(to: CGPoint(x: center.x - baseHalfWidth, y: baseY))
            wedge.addQuadCurve(
                to: CGPoint(x: center.x + baseHalfWidth, y: baseY),
                control: CGPoint(x: center.x, y: baseY + 3.9 * k)
            )
            wedge.closeSubpath()

            cg.saveGState()
            cg.addPath(wedge)
            cg.clip()

            let colors = [
                violet.withAlphaComponent(0.60).cgColor,
                violet.withAlphaComponent(0).cgColor
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: center.x, y: baseY),
                    end: CGPoint(x: center.x, y: tip.y),
                    options: []
                )
            }
            cg.restoreGState()
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func makeTopImage() -> UIImage? {
        // Wide enough for the scaled bike (~40pt) plus room for the shadows to fall off.
        let side: CGFloat = 56
        let center = CGPoint(x: side / 2, y: side / 2)

        return renderer(side).image { context in
            let cg = context.cgContext

            drawContactShadow(in: cg, center: center)

            // Without a disc behind it, the bike needs its own separation from the map —
            // Mapbox's night style renders roads noticeably lighter than buildings, and a bare
            // glyph on bare asphalt loses its edges. A transparency layer means the whole
            // glyph casts one shadow as a silhouette, rather than every tube shadowing the
            // parts beneath it and muddying the middle. Kept light, because the contact
            // shadow above is now doing most of the separating.
            cg.setShadow(
                offset: CGSize(width: 0, height: 0.5 * glyphScale),
                blur: 2.2 * glyphScale,
                color: UIColor.black.withAlphaComponent(0.5).cgColor
            )
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            drawBmx(in: cg, center: center)
            cg.endTransparencyLayer()
        }.withRenderingMode(.alwaysOriginal)
    }

    /// A soft ellipse under the tyres. This is what makes the bike read as an object resting on
    /// the map rather than a sticker floating above it — the single biggest difference between
    /// this and a flat icon, and the thing Waze's marker gets from being a real 3D model.
    ///
    /// It has to stay small and faint: an earlier, larger version read as a dark cloud behind
    /// the bike and looked worse than no shadow at all.
    private static func drawContactShadow(in cg: CGContext, center: CGPoint) {
        let k = glyphScale
        let groundY = center.y + 9.2 * k
        let radiusX = 8.2 * k
        let radiusY = 1.7 * k

        let colors = [
            UIColor.black.withAlphaComponent(0.46).cgColor,
            UIColor.black.withAlphaComponent(0.16).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.6, 1]
        ) else { return }

        cg.saveGState()
        // Squash the vertical axis so one radial gradient falls off as an ellipse.
        cg.translateBy(x: center.x, y: groundY)
        cg.scaleBy(x: 1, y: radiusY / radiusX)
        cg.translateBy(x: -center.x, y: -groundY)
        cg.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: center.x, y: groundY),
            startRadius: 0,
            endCenter: CGPoint(x: center.x, y: groundY),
            endRadius: radiusX,
            options: []
        )
        cg.restoreGState()
    }

    /// A 1980s BMX in side profile. Three things make it read as a BMX rather than a generic
    /// bicycle at this size, in priority order: fat tires, a level top tube on a compact frame,
    /// and high-rise bars. Violet on the fork, bars, and hubs picks out that cockpit against
    /// the ink body the way chrome did on the reference bike.
    private static func drawBmx(in cg: CGContext, center: CGPoint) {
        let k = glyphScale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * k, y: center.y + y * k)
        }

        let wheelRadius = 4.7 * k
        let rear = point(-7.4, 3.6)
        let front = point(7.4, 3.6)
        let bottomBracket = point(0.2, 4.3) // low, BMX-typical
        let seatTop = point(-4.3, -3.4)
        let headTop = point(5.2, -3.4)
        let headBottom = point(6.5, -0.6)

        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        // Tires — chunky rings. The thick stroke is the point; BMX tires are fat.
        //
        // Drawn twice: a rubber-dark ring first, then the ink ring slightly narrower on top, so
        // a hair of dark peeks out either side. That thin edge is doing two jobs — reading as
        // tyre against rim, and keeping the wheels defined over pale asphalt. A full-width dark
        // tyre was tried and turned the wheels into muddy blobs at puck size.
        cg.setStrokeColor(rubber.cgColor)
        cg.setLineWidth(3.05 * k)
        for hub in [rear, front] {
            cg.addEllipse(in: CGRect(
                x: hub.x - wheelRadius, y: hub.y - wheelRadius,
                width: wheelRadius * 2, height: wheelRadius * 2
            ))
        }
        cg.strokePath()

        cg.setStrokeColor(frameColor.cgColor)
        cg.setLineWidth(2.3 * k)
        for hub in [rear, front] {
            cg.addEllipse(in: CGRect(
                x: hub.x - wheelRadius, y: hub.y - wheelRadius,
                width: wheelRadius * 2, height: wheelRadius * 2
            ))
        }
        cg.strokePath()

        cg.setFillColor(hardwareColor.cgColor)
        for hub in [rear, front] {
            cg.addEllipse(in: CGRect(
                x: hub.x - 1.15 * k, y: hub.y - 1.15 * k,
                width: 2.3 * k, height: 2.3 * k
            ))
        }
        cg.fillPath()

        // Frame — stroked tubes rather than a filled wedge, so it reads as tubing.
        let frame = CGMutablePath()
        frame.move(to: seatTop); frame.addLine(to: headTop) // top tube
        frame.move(to: headTop); frame.addLine(to: bottomBracket) // down tube
        frame.move(to: seatTop); frame.addLine(to: bottomBracket) // seat tube
        frame.move(to: bottomBracket); frame.addLine(to: rear) // chain stay
        frame.move(to: seatTop); frame.addLine(to: rear) // seat stay
        cg.setStrokeColor(frameColor.cgColor)
        cg.setLineWidth(2.1 * k)
        cg.addPath(frame)
        cg.strokePath()

        let forkAndBars = CGMutablePath()
        forkAndBars.move(to: headTop); forkAndBars.addLine(to: headBottom) // head tube
        forkAndBars.move(to: headBottom); forkAndBars.addLine(to: front) // fork
        // High-rise bars — the BMX signature. Riser up, then grip swept back to the rider.
        forkAndBars.move(to: headTop)
        forkAndBars.addLine(to: CGPoint(x: headTop.x - 0.4 * k, y: headTop.y - 4.4 * k))
        forkAndBars.addLine(to: CGPoint(x: headTop.x - 3.4 * k, y: headTop.y - 4.9 * k))
        cg.setStrokeColor(hardwareColor.cgColor)
        cg.setLineWidth(1.95 * k)
        cg.addPath(forkAndBars)
        cg.strokePath()

        // Crossbar — reads as the pad bar.
        cg.setLineWidth(1.3 * k)
        cg.move(to: CGPoint(x: headTop.x - 0.2 * k, y: headTop.y - 2.4 * k))
        cg.addLine(to: CGPoint(x: headTop.x - 2.4 * k, y: headTop.y - 2.7 * k))
        cg.strokePath()

        // Seatpost, then the saddle on top of it.
        cg.setLineWidth(1.7 * k)
        cg.move(to: seatTop)
        cg.addLine(to: CGPoint(x: seatTop.x - 0.3 * k, y: seatTop.y - 1.9 * k))
        cg.strokePath()

        cg.setStrokeColor(frameColor.cgColor)
        cg.setLineWidth(2.0 * k)
        cg.move(to: CGPoint(x: seatTop.x - 2.2 * k, y: seatTop.y - 2.4 * k))
        cg.addLine(to: CGPoint(x: seatTop.x + 1.0 * k, y: seatTop.y - 2.1 * k))
        cg.strokePath()

        // Chainring
        cg.setFillColor(hardwareColor.cgColor)
        cg.addEllipse(in: CGRect(
            x: bottomBracket.x - 1.5 * k, y: bottomBracket.y - 1.5 * k,
            width: 3 * k, height: 3 * k
        ))
        cg.fillPath()
    }
}
