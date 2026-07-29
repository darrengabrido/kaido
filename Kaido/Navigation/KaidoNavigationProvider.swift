import MapboxNavigationCore

enum KaidoNavigationProvider {
    @MainActor
    static let shared = MapboxNavigationProvider(coreConfig: CoreConfig())
}
