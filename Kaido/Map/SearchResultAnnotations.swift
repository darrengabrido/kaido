import SwiftUI
import MapboxMaps

/// Pins each search result on the map with its name, the way Google Maps labels POIs directly
/// under a search instead of leaving them only in the results list in the drawer below. Mapbox
/// hides overlapping labels on its own (no `.allowOverlap`), so a dense result set thins out
/// naturally at street-level zoom instead of stacking illegibly.
struct SearchResultAnnotations: MapContent {
    let results: [SearchResult]
    let onSelect: (SearchResult) -> Void

    var body: some MapContent {
        ForEvery(results, id: \.id) { result in
            MapViewAnnotation(coordinate: result.coordinate) {
                SearchResultMarker(result: result) {
                    onSelect(result)
                }
            }
        }
    }
}

private struct SearchResultMarker: View {
    let result: SearchResult
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: result.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(Color.kaidoVioletOnMap, in: Circle())
                    .overlay {
                        Circle().stroke(Color.white, lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.32), radius: 3, y: 1)

                Text(result.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.kaidoInk)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.kaidoMidnight.opacity(0.92), in: Capsule())
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(result.name)
        .accessibilityHint("Selects this place")
    }
}
