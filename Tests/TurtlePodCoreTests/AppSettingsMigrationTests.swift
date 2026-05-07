import Foundation
import XCTest
@testable import TurtlePodCore

final class AppSettingsMigrationTests: XCTestCase {
    func testDecodesOlderSettingsWithOpenAIClassificationDefault() throws {
        let data = """
        {
          "aiAnalysisEnabled": true,
          "autoSkipEnabled": false,
          "adSkipConfidenceThreshold": 0.81
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.aiAnalysisEnabled)
        XCTAssertEqual(settings.aiClassificationProvider, .openAI)
        XCTAssertFalse(settings.autoSkipEnabled)
        XCTAssertEqual(settings.adSkipConfidenceThreshold, 0.81)
    }
}
