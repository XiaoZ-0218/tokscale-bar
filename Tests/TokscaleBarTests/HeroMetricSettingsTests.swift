import XCTest
@testable import TokscaleBar

final class HeroMetricSettingsTests: XCTestCase {
    /// Mirror of Settings.Key.heroMetric's raw value (the enum is private).
    private let key = "heroMetric"

    override func setUpWithError() throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testMissingKeyDefaultsToCost() {
        let settings = Settings()
        XCTAssertEqual(settings.heroMetric, .cost)
    }

    func testPersistedTokensReloadsAsTokens() {
        let settings = Settings()
        settings.heroMetric = .tokens
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "tokens")

        let reloaded = Settings()
        XCTAssertEqual(reloaded.heroMetric, .tokens)
    }

    func testInvalidRawValueFallsBackToCost() {
        UserDefaults.standard.set("messages", forKey: key)
        let settings = Settings()
        XCTAssertEqual(settings.heroMetric, .cost)
    }

    func testPersistsFalseDoesNotWriteTokens() {
        let settings = Settings()
        settings.persists = false
        settings.heroMetric = .tokens
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }
}
