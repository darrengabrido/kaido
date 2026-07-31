import Foundation
import SwiftUI

/// A generic, original bicycle illustration and profile summary. It deliberately mirrors the
/// reference screen's hierarchy without copying vendor artwork or exposing unsupported controls.
struct BikeShowcaseCard: View {
    let profile: BikeProfile
    let telemetry: BikeTelemetry
    let status: BikeBLEManager.ScanState
    let onEdit: () -> Void
    let onConnect: () -> Void
    let onTelemetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            header

            BikeSilhouette(type: profile.bikeType)
                .frame(height: 174)
                .padding(.horizontal, 8)

            HStack(spacing: 8) {
                profileTag
                Spacer()
                if let batteryPercent = telemetry.batteryPercent {
                    batteryTag(batteryPercent)
                } else {
                    Label(connectionText, systemImage: connectionSymbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(connectionColor)
                }
            }

            HStack(spacing: 0) {
                showcaseAction(
                    title: "Details",
                    systemImage: "slider.horizontal.3",
                    action: onEdit
                )

                Divider()
                    .frame(height: 34)

                showcaseAction(
                    title: telemetry.isConnected ? "Disconnect" : profile.isPaired ? "Reconnect" : "Connect",
                    systemImage: telemetry.isConnected ? "bolt.slash" : "bolt.horizontal.circle",
                    action: onConnect
                )

                Divider()
                    .frame(height: 34)

                showcaseAction(
                    title: "Live data",
                    systemImage: "gauge.with.dots.needle.67percent",
                    action: onTelemetry
                )
            }
            .padding(.vertical, 4)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.kaidoIndigo.opacity(0.58),
                            Color.kaidoMidnight.opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.kaidoViolet.opacity(0.2), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.name), \(profile.bikeType.title), \(connectionText)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.kaidoInk)
                    .lineLimit(1)

                Text(profile.rideTimeProfile.paceDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color.kaidoDim)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 7, height: 7)
                    Text(connectionText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.kaidoInk)
                }

                Text("\(BikeSpeed.mphText(fromKph: profile.preferredCruisingSpeedKph)) mph pace")
                    .font(.caption2)
                    .foregroundStyle(Color.kaidoDim)
            }
        }
    }

    private var profileTag: some View {
        Label(profile.bikeType.title, systemImage: profile.bikeType.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.kaidoInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.kaidoInk.opacity(0.1), in: Capsule())
    }

    private var connectionText: String {
        switch status {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .scanning: "Scanning"
        case .bluetoothUnavailable: "Bluetooth off"
        case .idle: profile.isPaired ? "Ready to reconnect" : "Not paired"
        }
    }

    private var connectionSymbol: String {
        switch status {
        case .connected: "checkmark.circle.fill"
        case .connecting, .scanning: "arrow.triangle.2.circlepath"
        case .bluetoothUnavailable: "bolt.slash.fill"
        case .idle: "bolt.horizontal.circle"
        }
    }

    private var connectionColor: Color {
        switch status {
        case .connected: .statusGood
        case .connecting, .scanning: .statusCaution
        case .bluetoothUnavailable: .statusCritical
        case .idle: .kaidoDim
        }
    }

    private func batteryTag(_ percent: Int) -> some View {
        Label("\(percent)%", systemImage: batterySymbol(percent))
            .font(.caption.weight(.medium))
            .foregroundStyle(batteryColor(percent))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(batteryColor(percent).opacity(0.12), in: Capsule())
    }

    private func showcaseAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(Color.kaidoInk)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func batteryColor(_ percent: Int) -> Color {
        switch percent {
        case ..<20: .statusCritical
        case ..<50: .statusCaution
        default: .statusGood
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case 0...12: "battery.0percent"
        case 13...37: "battery.25percent"
        case 38...62: "battery.50percent"
        case 63...87: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// A technical side-profile drawing. All tubes terminate at the appropriate axle, bottom
/// bracket, or head-tube point so the illustration reads as a real bicycle rather than an icon
/// assembled from loosely connected lines.
private struct BikeSilhouette: View {
    let type: BikeType

    var body: some View {
        GeometryReader { proxy in
            let geometry = BikeDrawingGeometry(size: proxy.size)

            ZStack {
                wheel(center: geometry.rearAxle, radius: geometry.wheelRadius)
                wheel(center: geometry.frontAxle, radius: geometry.wheelRadius)

                BikeFrameShape(geometry: geometry)
                    .stroke(
                        Color.kaidoInk.opacity(0.92),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )

                BikeControlsShape(geometry: geometry)
                    .stroke(
                        Color.kaidoInk.opacity(0.9),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )

                BikeDrivetrainShape(geometry: geometry)
                    .stroke(
                        Color.kaidoDim.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                Capsule()
                    .fill(Color.kaidoInk.opacity(0.92))
                    .frame(width: max(28, geometry.size.width * 0.095), height: 5)
                    .rotationEffect(.degrees(5))
                    .position(
                        x: (geometry.saddleBack.x + geometry.saddleFront.x) / 2,
                        y: geometry.saddleBack.y
                    )

                Capsule()
                    .fill(Color.kaidoInk.opacity(0.9))
                    .frame(width: 15, height: 4)
                    .rotationEffect(.degrees(42))
                    .position(geometry.handlebarGrip)

                Circle()
                    .fill(Color.kaidoInk.opacity(0.82))
                    .frame(width: 7, height: 7)
                    .position(geometry.rearAxle)

                Circle()
                    .fill(Color.kaidoInk.opacity(0.82))
                    .frame(width: 7, height: 7)
                    .position(geometry.frontAxle)

                if type == .electric || type == .cargo {
                    BikeBatteryPack(
                        start: geometry.batteryStart,
                        end: geometry.batteryEnd,
                        thickness: geometry.batteryThickness
                    )

                    BikeMotor(center: geometry.bottomBracket)
                } else {
                    Circle()
                        .stroke(Color.kaidoInk.opacity(0.88), lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .position(geometry.bottomBracket)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func wheel(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.kaidoDim.opacity(0.85), lineWidth: 3)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)

            Circle()
                .stroke(Color.kaidoInk.opacity(0.18), lineWidth: 1)
                .frame(width: radius * 1.84, height: radius * 1.84)
                .position(center)

            BikeSpokesShape(center: center, radius: radius)
                .stroke(Color.kaidoDim.opacity(0.42), lineWidth: 0.8)
        }
    }
}

private struct BikeDrawingGeometry {
    let size: CGSize

    private func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: size.width * x, y: size.height * y)
    }

    var rearAxle: CGPoint { point(x: 0.20, y: 0.72) }
    var frontAxle: CGPoint { point(x: 0.80, y: 0.72) }
    var bottomBracket: CGPoint { point(x: 0.48, y: 0.60) }
    var seatCluster: CGPoint { point(x: 0.38, y: 0.31) }
    var headTubeTop: CGPoint { point(x: 0.64, y: 0.32) }
    var headTubeBottom: CGPoint { point(x: 0.66, y: 0.42) }
    var seatPostTop: CGPoint { point(x: 0.35, y: 0.24) }
    var saddleBack: CGPoint { point(x: 0.29, y: 0.235) }
    var saddleFront: CGPoint { point(x: 0.40, y: 0.245) }
    var stemEnd: CGPoint { point(x: 0.71, y: 0.235) }
    var handlebarTop: CGPoint { point(x: 0.755, y: 0.19) }
    var handlebarGrip: CGPoint { point(x: 0.79, y: 0.22) }
    var crankEnd: CGPoint { point(x: 0.545, y: 0.66) }
    var pedalEnd: CGPoint { point(x: 0.59, y: 0.66) }
    var oppositeCrankEnd: CGPoint { point(x: 0.42, y: 0.545) }
    var oppositePedalEnd: CGPoint { point(x: 0.385, y: 0.545) }
    var wheelRadius: CGFloat { min(size.width * 0.15, size.height * 0.30) }
    var batteryThickness: CGFloat { max(12, size.width * 0.038) }

    var batteryStart: CGPoint {
        interpolate(from: bottomBracket, to: headTubeBottom, progress: 0.18)
    }

    var batteryEnd: CGPoint {
        interpolate(from: bottomBracket, to: headTubeBottom, progress: 0.76)
    }

    private func interpolate(
        from start: CGPoint,
        to end: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }
}

private struct BikeFrameShape: Shape {
    let geometry: BikeDrawingGeometry

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Rear triangle: rear dropout → bottom bracket → seat cluster → rear dropout.
        path.move(to: geometry.rearAxle)
        path.addLine(to: geometry.bottomBracket)
        path.addLine(to: geometry.seatCluster)
        path.addLine(to: geometry.rearAxle)

        // Main triangle: seat cluster → head tube → bottom bracket.
        path.move(to: geometry.seatCluster)
        path.addLine(to: geometry.headTubeTop)
        path.addLine(to: geometry.headTubeBottom)
        path.addLine(to: geometry.bottomBracket)

        // Front fork terminates at the front hub, not the down tube.
        path.move(to: geometry.headTubeBottom)
        path.addLine(to: geometry.frontAxle)

        return path
    }
}

private struct BikeControlsShape: Shape {
    let geometry: BikeDrawingGeometry

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Seat post and saddle.
        path.move(to: geometry.seatCluster)
        path.addLine(to: geometry.seatPostTop)
        path.move(to: geometry.saddleBack)
        path.addLine(to: geometry.saddleFront)

        // Stem and swept handlebar.
        path.move(to: geometry.headTubeTop)
        path.addLine(to: geometry.stemEnd)
        path.addLine(to: geometry.handlebarTop)
        path.addLine(to: geometry.handlebarGrip)

        return path
    }
}

private struct BikeDrivetrainShape: Shape {
    let geometry: BikeDrawingGeometry

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: geometry.bottomBracket)
        path.addLine(to: geometry.crankEnd)
        path.addLine(to: geometry.pedalEnd)
        path.move(to: geometry.bottomBracket)
        path.addLine(to: geometry.oppositeCrankEnd)
        path.addLine(to: geometry.oppositePedalEnd)
        return path
    }
}

private struct BikeSpokesShape: Shape {
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = radius * 0.82
        let ends = [
            CGPoint(x: center.x + inset, y: center.y),
            CGPoint(x: center.x - inset, y: center.y),
            CGPoint(x: center.x, y: center.y + inset),
            CGPoint(x: center.x, y: center.y - inset),
            CGPoint(x: center.x + inset * 0.7, y: center.y + inset * 0.7),
            CGPoint(x: center.x - inset * 0.7, y: center.y - inset * 0.7),
            CGPoint(x: center.x + inset * 0.7, y: center.y - inset * 0.7),
            CGPoint(x: center.x - inset * 0.7, y: center.y + inset * 0.7)
        ]

        var path = Path()
        for end in ends {
            path.move(to: center)
            path.addLine(to: end)
        }
        return path
    }
}

private struct BikeBatteryPack: View {
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat

    var body: some View {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = max((deltaX * deltaX + deltaY * deltaY).squareRoot(), 1)
        let center = CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
        let angle = Angle(radians: atan2(Double(deltaY), Double(deltaX)))

        RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.kaidoVioletOnMap, Color.kaidoViolet],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
                    .stroke(Color.kaidoInk.opacity(0.46), lineWidth: 1)
            }
            .frame(width: length, height: thickness)
            .rotationEffect(angle)
            .shadow(color: Color.kaidoViolet.opacity(0.42), radius: 6)
            .position(center)
    }
}

private struct BikeMotor: View {
    let center: CGPoint

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.kaidoMidnight.opacity(0.92))
            Circle()
                .stroke(Color.kaidoVioletOnMap.opacity(0.9), lineWidth: 2)
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.routeTealOnMap)
        }
        .frame(width: 22, height: 22)
        .shadow(color: Color.kaidoViolet.opacity(0.32), radius: 5)
        .position(center)
    }
}
