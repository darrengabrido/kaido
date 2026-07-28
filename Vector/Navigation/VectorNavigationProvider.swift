import MapboxNavigationCore

enum VectorNavigationProvider {
    @MainActor
    static let shared = MapboxNavigationProvider(
        // Must match DirectionsService's cycling profile — mismatched tiles break active
        // guidance / reroute when starting NavigationViewController.
        coreConfig: CoreConfig(
            routingConfig: RoutingConfig(datasetProfileIdentifier: .cycling)
        )
    )
}
