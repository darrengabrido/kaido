import MapboxNavigationCore

enum EbikeNavigationProvider {
    @MainActor
    static let shared = MapboxNavigationProvider(coreConfig: CoreConfig())
}
