import MapboxNavigationCore
import MapboxNavigationUIKit
import SwiftUI

/// Liquid Glass replacement for Mapbox's opaque `BottomBannerViewController`.
struct GlassBottomBanner: View {
    let model: NavigationBannerModel
    let telemetry: BikeTelemetry
    let onEnd: () -> Void
    @State private var isPresentingDetails = false

    var body: some View {
        content
            .sheet(isPresented: $isPresentingDetails) {
                NavigationDetailsSheet(model: model, telemetry: telemetry)
                    .presentationDetents([.medium, .large])
            }
    }

    private var content: some View {
        VStack(spacing: 8) {
            progressBar

            HStack(spacing: 16) {
                // Only this region opens the details sheet — keeping it a sibling of the End
                // button rather than a parent tap gesture stops the two from competing.
                Button {
                    isPresentingDetails = true
                } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(NavigationBannerModel.durationText(model.durationRemaining))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.kaidoInk)
                            Text("Your ride time")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.kaidoVioletOnMap)
                            Text(NavigationBannerModel.distanceText(model.distanceRemaining))
                                .font(.subheadline)
                                .foregroundStyle(Color.kaidoDim)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(model.arrivalDate.formatted(date: .omitted, time: .shortened))
                                .font(.headline)
                            Text("Arrival")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ride details")

                Button(action: onEnd) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End navigation")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                Capsule()
                    // Lighter variant: this sits on glass, where the base violet washes out.
                    .fill(Color.kaidoVioletOnMap)
                    .frame(width: proxy.size.width * min(max(model.fractionTraveled, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

/// Hosts ``GlassBottomBanner`` so it can be handed to `NavigationOptions(bottomBanner:)`.
final class GlassBottomBannerController: UIHostingController<GlassBottomBanner>, NavigationComponent {
    private let model: NavigationBannerModel

    /// Set once the navigation controller exists, so End routes through Mapbox's own cancel path
    /// (`didTapCancel`) rather than a parallel teardown that could drift from it.
    weak var navigationViewController: NavigationViewController?

    init(model: NavigationBannerModel, telemetry: BikeTelemetry) {
        self.model = model
        super.init(rootView: GlassBottomBanner(model: model, telemetry: telemetry, onEnd: {}))
        view.backgroundColor = .clear
        rootView = GlassBottomBanner(model: model, telemetry: telemetry) { [weak self] in
            guard let self else { return }
            self.navigationViewController?.didTapCancel(self)
        }
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func onRouteProgressUpdated(_ progress: RouteProgress) {
        model.update(with: progress)
    }
}
