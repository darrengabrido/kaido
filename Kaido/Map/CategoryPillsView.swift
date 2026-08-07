import SwiftUI

/// Horizontal row of category filter pills shown above the search results list — "All" plus
/// one pill per distinct category present in the current results. Selecting a pill filters
/// both the results list and the candidate pins shown on the map.
struct CategoryPillsView: View {
    let categories: [PlaceCategoryTally]
    @Binding var selected: PlaceCategory?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                pill(label: "All", iconName: nil, isSelected: selected == nil) {
                    selected = nil
                }

                ForEach(categories) { entry in
                    pill(
                        label: entry.category.label,
                        iconName: entry.category.iconName,
                        isSelected: selected == entry.category
                    ) {
                        selected = (selected == entry.category) ? nil : entry.category
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func pill(
        label: String,
        iconName: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isSelected ? Color.kaidoVioletOnMap : Color.kaidoDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.kaidoViolet.opacity(0.18) : Color.kaidoInk.opacity(0.07),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(Color.kaidoInk.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
