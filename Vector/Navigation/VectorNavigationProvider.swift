import MapboxNavigationCore

enum VectorNavigationProvider {
    @MainActor
    static let shared = MapboxNavigationProvider(coreConfig: CoreConfig())
}
