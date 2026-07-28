import SwiftUI
import SwiftData

struct RoutesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    @State private var isShowingPlanner = false

    var body: some View {
        NavigationStack {
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
                                .tint(.vectorViolet)
                            }
                        }
                        .onDelete(perform: deleteRoutes)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Routes")
            .navigationDestination(for: Route.self) { route in
                RouteDetailView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingPlanner = true
                    } label: {
                        Label("New Route", systemImage: "plus")
                    }
                    .tint(.vectorViolet)
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

private struct RouteRow: View {
    let route: Route

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vectorDim.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(Color.vectorDim)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(route.name)
                        .font(.subheadline.weight(.medium))
                    if route.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.vectorViolet)
                    }
                }
                Text(formattedDistance(route.distanceMeters))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.vectorDim)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.vectorDim.opacity(0.14))
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
        .modelContainer(VectorModelContainer.shared)
}
