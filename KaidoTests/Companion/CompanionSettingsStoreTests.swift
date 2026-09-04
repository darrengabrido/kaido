@testable import Kaido
import XCTest

@MainActor
final class CompanionSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CompanionSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(
        secrets: InMemorySecretStore = InMemorySecretStore(),
        bundledOpenAIKey: String? = nil
    ) -> CompanionSettingsStore {
        CompanionSettingsStore(defaults: defaults, secrets: secrets, bundledOpenAIKey: bundledOpenAIKey)
    }

    func testFreshInstallWithNoKeysUsesBuiltInPicks() {
        let store = makeStore()
        XCTAssertEqual(store.provider, .openAI)
        XCTAssertEqual(store.configurationSource, .builtIn)
        XCTAssertNil(store.activeConfiguration)
    }

    func testBundledOpenAIKeyIsUsedWhenRiderHasNone() {
        let store = makeStore(bundledOpenAIKey: "sk-bundled")
        XCTAssertEqual(store.configurationSource, .bundledKey)
        XCTAssertEqual(
            store.activeConfiguration,
            CompanionConfiguration(provider: .openAI, model: AIProvider.openAI.defaultModel, apiKey: "sk-bundled")
        )
    }

    func testRiderKeyWinsOverBundledKey() {
        let store = makeStore(bundledOpenAIKey: "sk-bundled")
        store.setAPIKey("  sk-mine  ", for: .openAI)
        XCTAssertEqual(store.configurationSource, .riderKey(.openAI))
        XCTAssertEqual(store.activeConfiguration?.apiKey, "sk-mine")
    }

    func testBundledKeyDoesNotLeakIntoOtherProviders() {
        let store = makeStore(bundledOpenAIKey: "sk-bundled")
        store.setProvider(.anthropic)
        XCTAssertEqual(store.configurationSource, .builtIn)
        XCTAssertNil(store.activeConfiguration)
    }

    func testOffAlwaysMeansBuiltInEvenWithKeys() {
        let store = makeStore(bundledOpenAIKey: "sk-bundled")
        store.setAPIKey("sk-ant-mine", for: .anthropic)
        store.setProvider(.off)
        XCTAssertEqual(store.configurationSource, .builtIn)
        XCTAssertNil(store.activeConfiguration)
        XCTAssertEqual(store.statusDescription, "Free Ride is using built-in suggestions.")
    }

    func testEachProviderKeepsItsOwnKeyAndModel() {
        let store = makeStore()
        store.setAPIKey("sk-ant", for: .anthropic)
        store.setAPIKey("AIza", for: .gemini)
        store.setModel("claude-sonnet-5", for: .anthropic)

        store.setProvider(.anthropic)
        XCTAssertEqual(
            store.activeConfiguration,
            CompanionConfiguration(provider: .anthropic, model: "claude-sonnet-5", apiKey: "sk-ant")
        )

        store.setProvider(.gemini)
        XCTAssertEqual(
            store.activeConfiguration,
            CompanionConfiguration(provider: .gemini, model: AIProvider.gemini.defaultModel, apiKey: "AIza")
        )
    }

    func testEmptyKeyRemovesTheStoredOne() {
        let secrets = InMemorySecretStore()
        let store = makeStore(secrets: secrets)
        store.setAPIKey("xai-1", for: .grok)
        XCTAssertTrue(store.hasAPIKey(for: .grok))
        store.setAPIKey("   ", for: .grok)
        XCTAssertFalse(store.hasAPIKey(for: .grok))
        XCTAssertNil(secrets.read(account: AIProvider.grok.rawValue))
    }

    func testProviderModelAndKeyPresenceSurviveRelaunch() {
        let secrets = InMemorySecretStore()
        do {
            let store = makeStore(secrets: secrets)
            store.setProvider(.grok)
            store.setModel("grok-3-mini", for: .grok)
            store.setAPIKey("xai-1", for: .grok)
        }
        let relaunched = makeStore(secrets: secrets)
        XCTAssertEqual(relaunched.provider, .grok)
        XCTAssertEqual(relaunched.model(for: .grok), "grok-3-mini")
        XCTAssertTrue(relaunched.hasAPIKey(for: .grok))
        XCTAssertEqual(relaunched.statusDescription, "Free Ride is using xAI Grok · grok-3-mini")
    }

    func testPlaceholderBundledKeyIsIgnored() {
        let bundle = Bundle(for: CompanionSettingsStoreTests.self)
        // The test bundle has no OpenAIAPIKey at all, which must read as "no key".
        XCTAssertNil(CompanionSettingsStore.bundledOpenAIKeyFromInfoPlist(bundle: bundle))
    }
}
