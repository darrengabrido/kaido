import MapboxNavigationCore
import MapboxNavigationUIKit
import SwiftUI

/// Liquid Glass replacement for Mapbox's opaque `TopBannerViewController`.
struct GlassTopBanner: View {
    let model: NavigationBannerModel
    @State private var isPresentingSteps = false

    var body: some View {
        content
            .onTapGesture { isPresentingSteps = true }
            .sheet(isPresented: $isPresentingSteps) {
                NavigationStepsSheet(steps: model.remainingSteps)
            }
    }

    private var content: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Image(systemName: maneuverSymbol)
                    .font(.system(size: 28, weight: .semibold))
                    // Glass lightens what sits on it — the base violet only clears ~3.4:1 here.
                    .foregroundStyle(Color.vectorVioletOnMap)
                Text(NavigationBannerModel.distanceText(model.distanceToManeuver))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.vectorDim)
            }
            .frame(minWidth: 58)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.instruction?.primaryInstruction.text ?? "")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let secondary = model.instruction?.secondaryInstruction?.text {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var maneuverSymbol: String {
        NavigationBannerModel.maneuverSymbol(
            type: model.instruction?.primaryInstruction.maneuverType,
            direction: model.instruction?.primaryInstruction.maneuverDirection
        )
    }
}

/// Hosts ``GlassTopBanner`` so it can be handed to `NavigationOptions(topBanner:)`.
final class GlassTopBannerController: UIHostingController<GlassTopBanner>, NavigationComponent {
    private let model: NavigationBannerModel

    init(model: NavigationBannerModel) {
        self.model = model
        super.init(rootView: GlassTopBanner(model: model))
        view.backgroundColor = .clear
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func onDidPassVisualInstructionPoint(_ instruction: VisualInstructionBanner) {
        model.instruction = instruction
    }

    func onRouteProgressUpdated(_ progress: RouteProgress) {
        model.update(with: progress)
    }
}
