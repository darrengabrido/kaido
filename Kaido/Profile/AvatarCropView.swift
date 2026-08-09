import SwiftUI

/// A pinch-to-zoom, drag-to-reposition circular crop step shown right after a photo is picked, so
/// the saved avatar is framed the way the rider actually wants rather than an arbitrary center-crop.
struct AvatarCropView: View {
    let image: UIImage
    var onCancel: () -> Void
    var onConfirm: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let cropDiameter: CGFloat = 280
    private let outputDimension: CGFloat = 320
    private let maxScale: CGFloat = 4

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kaidoMidnight.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()
                    cropViewport
                    Text("Pinch and drag to reposition")
                        .font(.subheadline)
                        .foregroundStyle(Color.kaidoDim)
                    Spacer()
                }
            }
            .navigationTitle("Move and Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose Photo") {
                        onConfirm(renderCroppedImage())
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cropViewport: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cropDiameter, height: cropDiameter)
                .scaleEffect(scale)
                .offset(offset)
                .clipShape(Circle())

            CropOverlayShape(cropDiameter: cropDiameter)
                .fill(Color.kaidoMidnight.opacity(0.7), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: cropDiameter, height: cropDiameter)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(maxScale, max(1, lastScale * value))
                        clampOffset()
                    }
                    .onEnded { _ in lastScale = scale },
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                        clampOffset()
                    }
                    .onEnded { _ in lastOffset = offset }
            )
        )
        .accessibilityLabel("Photo preview")
        .accessibilityHint("Pinch to zoom or drag to reposition, then choose photo when ready")
    }

    /// Matches SwiftUI's own `scaledToFill()` behavior: the image is scaled up just enough that
    /// both dimensions cover the crop circle's bounding square, before the user's own zoom/pan.
    private var fillScale: CGFloat {
        max(cropDiameter / image.size.width, cropDiameter / image.size.height)
    }

    /// Keeps the image covering the crop circle at all times — without this, zooming out or
    /// panning too far would reveal blank space inside the circle.
    private func clampOffset() {
        let scaledSize = CGSize(
            width: image.size.width * fillScale * scale,
            height: image.size.height * fillScale * scale
        )
        let maxX = max(0, (scaledSize.width - cropDiameter) / 2)
        let maxY = max(0, (scaledSize.height - cropDiameter) / 2)
        offset.width = min(max(offset.width, -maxX), maxX)
        offset.height = min(max(offset.height, -maxY), maxY)
    }

    /// Re-renders the same fill → scale → offset transform shown in the interactive preview, at
    /// `outputDimension` instead of the on-screen `cropDiameter` — every term in the transform
    /// scales by the same `outputDimension / cropDiameter` factor, so the result is a
    /// higher-resolution capture of exactly what was framed inside the crop circle on screen.
    private func renderCroppedImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputDimension, height: outputDimension))
        return renderer.image { _ in
            let outputFillScale = max(outputDimension / image.size.width, outputDimension / image.size.height)
            let totalScale = outputFillScale * scale
            let scaledSize = CGSize(width: image.size.width * totalScale, height: image.size.height * totalScale)

            let offsetScale = outputDimension / cropDiameter
            let origin = CGPoint(
                x: (outputDimension - scaledSize.width) / 2 + offset.width * offsetScale,
                y: (outputDimension - scaledSize.height) / 2 + offset.height * offsetScale
            )
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
}

/// Everything outside a centered circle of `cropDiameter`, via the even-odd fill rule — darkens
/// the part of the picked photo that won't end up in the saved avatar.
private struct CropOverlayShape: Shape {
    let cropDiameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addEllipse(in: CGRect(
            x: rect.midX - cropDiameter / 2,
            y: rect.midY - cropDiameter / 2,
            width: cropDiameter,
            height: cropDiameter
        ))
        return path
    }
}
