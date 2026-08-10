import SwiftUI

/// The "Community" section of the Routes tab — see `CommunityRoutesViewModel` and
/// `CuratedCommunityRoutes` for where the data comes from.
struct CommunityRoutesListView: View {
    @State private var viewModel = CommunityRoutesViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.routes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.routes.isEmpty {
                ContentUnavailableView(
                    "Couldn't Load Community Routes",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if viewModel.routes.isEmpty {
                ContentUnavailableView(
                    "No Community Routes Yet",
                    systemImage: "person.3",
                    description: Text("Check back soon for routes curated by the Kaido team.")
                )
            } else {
                List {
                    ForEach(viewModel.routes) { route in
                        NavigationLink(value: route) {
                            CommunityRouteRow(route: route)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.refresh() }
            }
        }
        .task { await viewModel.load() }
    }
}

private struct CommunityRouteRow: View {
    let route: CommunityRoute

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.routeTeal.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: "map.fill")
                    .foregroundStyle(Color.routeTeal)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.subheadline.weight(.medium))
                if let areaName = route.areaName {
                    Text(areaName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(formattedDistance(route.distanceMeters))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.routeTeal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.routeTeal.opacity(0.14))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDistance(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

#Preview {
    NavigationStack {
        CommunityRoutesListView()
            .navigationTitle("Community")
    }
}
