import SwiftUI
import SwiftData

enum RoutesSection: String, CaseIterable, Identifiable {
    case custom
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom: "Custom"
        case .community: "Community"
        }
    }
}

struct RoutesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    @State private var isShowingPlanner = false
    @State private var section: RoutesSection = .custom

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Routes section", selection: $section) {
                    ForEach(RoutesSection.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                switch section {
                case .custom:
                    CustomRoutesSection(routes: routes, deleteRoutes: deleteRoutes)
                case .community:
                    CommunityRoutesListView()
                }
            }
            .navigationTitle("Routes")
            .navigationDestination(for: Route.self) { route in
                RouteDetailView(route: route)
            }
            .navigationDestination(for: CommunityRoute.self) { route in
                CommunityRouteDetailView(route: route)
            }
            .toolbar {
                if section == .custom {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isShowingPlanner = true
                        } label: {
                            Label("New Route", systemImage: "plus")
                        }
                        .tint(.kaidoViolet)
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingPlanner) {
                RoutePlannerView()
            }
        }
    }

    private func deleteRoutes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(routes[index])
        }
    }
}

private struct CustomRoutesSection: View {
    let routes: [Route]
    let deleteRoutes: (IndexSet) -> Void

    var body: some View {
        Group {
            if routes.isEmpty {
                ContentUnavailableView(
                    "No Routes Yet",
                    systemImage: "map",
                    description: Text("Draw a custom route on the map to see it here.")
                )
            } else {
                List {
                    ForEach(routes) { route in
                        NavigationLink(value: route) {
                            RouteRow(route: route)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading) {
                            Button {
                                route.isFavorite.toggle()
                            } label: {
                                Label(
                                    route.isFavorite ? "Unfavorite" : "Favorite",
                                    systemImage: route.isFavorite ? "star.slash" : "star.fill"
                                )
                            }
                            .tint(.kaidoViolet)
                        }
                    }
                    .onDelete(perform: deleteRoutes)
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct RouteRow: View {
    let route: Route

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.kaidoDim.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(Color.kaidoDim)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(route.name)
                        .font(.subheadline.weight(.medium))
                    if route.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.kaidoViolet)
                    }
                }
                Text(formattedDistance(route.distanceMeters))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.kaidoDim)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.kaidoDim.opacity(0.14))
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
    RoutesListView()
        .modelContainer(KaidoModelContainer.shared)
}
