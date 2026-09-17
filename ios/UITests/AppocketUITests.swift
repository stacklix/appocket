import XCTest
final class AppocketUITests: XCTestCase {
    func testBundledSentraLoadsAndBridgePersistsPreferences() throws {
        let app = XCUIApplication(); app.launch()
        let sentra = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sentra")).firstMatch
        XCTAssertTrue(sentra.waitForExistence(timeout: 15)); sentra.tap()
        let settings = app.webViews.buttons["连接设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Sentra-iPhone"; screenshot.lifetime = .keepAlways; add(screenshot)
        settings.tap()
        let url = app.webViews.textFields.matching(NSPredicate(format: "placeholderValue == %@", "https://api.openai.com/v1")).firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 5)); if url.value as? String != "https://api.openai.com/v1" { url.tap(); url.typeText("https://api.openai.com/v1") }
        let model = app.webViews.textFields.matching(NSPredicate(format: "placeholderValue == %@", "服务商提供的模型名称")).firstMatch
        if model.value as? String != "test-model" { model.tap(); model.typeText("test-model") }
        app.webViews.firstMatch.swipeUp()
        app.webViews.buttons["保存设置"].tap()
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "连接设置已保存")).firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Sentra")).firstMatch.tap()
        XCTAssertTrue(app.webViews.buttons["连接设置"].waitForExistence(timeout: 20)); app.webViews.buttons["连接设置"].tap()
        XCTAssertEqual(app.webViews.textFields.matching(NSPredicate(format: "placeholderValue == %@", "服务商提供的模型名称")).firstMatch.value as? String, "test-model")
    }
}
