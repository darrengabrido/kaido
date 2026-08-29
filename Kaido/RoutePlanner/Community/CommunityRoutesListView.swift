import SwiftUI

/// The "Community" section of the Routes tab — see `CommunityRoutesViewModel` and
/// `CommunityRouteService` for where the data comes from.
struct CommunityRoutesListView: View {
    @State private var viewModel = CommunityRoutesViewModel()
    @State private var removeErrorMessage: String?

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
                    description: Text("Check back soon for routes shared by the Kaido community.")
                )
            } else {
                List {
                    ForEach(viewModel.routes) { route in
                        NavigationLink(value: route) {
                            CommunityRouteRow(route: route)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            if viewModel.isMine(route) {
                                Button(role: .destructive) {
                                    Task { await remove(route) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await viewModel.refresh() }
            }
        }
        .task { await viewModel.load() }
        .alert("Couldn't Remove Route", isPresented: removeErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removeErrorMessage ?? "")
        }
    }

    private var removeErrorBinding: Binding<Bool> {
        Binding(
            get: { removeErrorMessage != nil },
            set: { isPresented in if !isPresented { removeErrorMessage = nil } }
        )
    }

    private func remove(_ route: CommunityRoute) async {
        do {
            try await viewModel.remove(route)
        } catch {
            removeErrorMessage = error.localizedDescription
        }
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

                HStack(spacing: 6) {
                    Text(formattedDistance(route.distanceMeters))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.routeTeal)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.routeTeal.opacity(0.14))
                        .clipShape(Capsule())

                    Text("· \(route.authorDisplayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(route.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
