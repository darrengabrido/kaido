import SwiftUI
import UIKit

/// The user location puck's bearing image — a bike instead of Mapbox's default arrow, since
/// this is what you're riding, not just a direction. Shared by every map that shows the puck
/// (browsing, route preview, and turn-by-turn) so "you" looks the same everywhere.
enum BikePuckImage {
    static let bearing: UIImage? = UIImage(
        systemName: "bicycle",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
    )?.withTintColor(UIColor(Color.kaidoVioletOnMap), renderingMode: .alwaysOriginal)
}
