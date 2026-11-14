import XCTest
import SubspaceCore

/// UI automation stays in XCTest; new non-UI behavior tests use Swift Testing.
@MainActor final class SubspaceUITests: XCTestCase {
    private var app: XCUIApplication!
    private let tabs = ["Overview", "Subscriptions", "Analytics", "Settings"]
    private let bottoms = ["overviewBottom", "subscriptionsBottom", "analyticsBottom", "settingsBottom"]
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { app?.terminate(); XCUIDevice.shared.orientation = .portrait }

    func testEmptyTabsAndSafeAreas() throws {
        try launch(populated: false)
        for (index, tab) in tabs.enumerated() {
            open(tab)
            XCTAssertTrue(element("addSubscription").isHittable)
            assertNavigation()
            if tab == "Analytics" { XCTAssertFalse(element("spendingChart").exists) }
            capture("Empty-\(tab)-Top")
            revealAboveTabBar(bottoms[index])
            capture("Empty-\(tab)-Bottom")
        }
    }
    func testAddSubscriptionAndPersistenceAcrossLaunches() throws {
        try launch(populated: false)
        element("addSubscription").tap()
        let custom = element("createCustomSubscription")
        XCTAssertTrue(custom.waitForExistence(timeout: 10)); custom.tap()
        let name = app.textFields["serviceName"]
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText("My subscription")
        let amount = app.textFields["paymentAmount"]
        if !amount.isHittable { swipeUp() }
        amount.tap(); amount.typeText("12.99")
        element("saveSubscription").tap()
        XCTAssertTrue(element("monthlyAverage").waitForExistence(timeout: 10))
        XCTAssertTrue(element("monthlyAverage").label.contains("12.99"))
        capture("Added-Overview")
        app.terminate()
        app.launchEnvironment["SUBSPACE_UI_TEST_RESET"] = "0"
        app.launch()
        XCTAssertTrue(element("monthlyAverage").waitForExistence(timeout: 10))
        XCTAssertTrue(element("monthlyAverage").label.contains("12.99"))
        open("Subscriptions")
        XCTAssertTrue(element("subscriptionRow-My subscription").waitForExistence(timeout: 10))
        element("addSubscription").tap()
        XCTAssertTrue(element("createCustomSubscription").waitForExistence(timeout: 10))
        capture("Add-From-Subscriptions")
    }
    func testPopulatedTabsChartsAndBottoms() throws {
        try launch(populated: true)
        for (index, tab) in tabs.enumerated() {
            open(tab); assertNavigation(); capture("Populated-\(tab)-Top")
            if tab == "Analytics" {
                let chart = element("spendingChart")
                XCTAssertTrue(chart.exists)
                chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()
                capture("Analytics-Annual-Selection")
                app.segmentedControls.buttons["Monthly"].tap()
                capture("Analytics-Monthly")
            }
            revealAboveTabBar(bottoms[index]); capture("Populated-\(tab)-Bottom")
        }
        app.terminate()
        app.launchEnvironment["SUBSPACE_UI_TEST_RESET"] = "0"
        app.launchEnvironment.removeValue(forKey: "SUBSPACE_UI_TEST_BACKUP")
        app.launch()
        open("Subscriptions")
        XCTAssertTrue(element("subscriptionRow-Plan 01").waitForExistence(timeout: 10))
    }
    func testLargeTextLightAppearanceAndReducedMotion() throws {
        try launch(populated: true, largeText: true, light: true, reducedMotion: true)
        for (index, tab) in tabs.enumerated() {
            open(tab); assertNavigation(); capture("Accessibility-Light-\(tab)-Top")
            revealAboveTabBar(bottoms[index]); capture("Accessibility-Light-\(tab)-Bottom")
        }
    }
    func testLandscapeSafeAreas() throws {
        try launch(populated: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        open("Overview"); assertNavigation(); capture("Landscape-Overview")
        revealAboveTabBar("overviewBottom"); capture("Landscape-Overview-Bottom")
        open("Settings"); assertNavigation(); capture("Landscape-Settings")
        revealAboveTabBar("settingsBottom"); capture("Landscape-Settings-Bottom")
    }
    private func launch(populated: Bool, largeText: Bool = false, light: Bool = false, reducedMotion: Bool = false) throws {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launchEnvironment = ["SUBSPACE_UI_TEST_ID": UUID().uuidString, "SUBSPACE_UI_TEST_RESET": "1", "SUBSPACE_UI_TEST_LARGE_TEXT": largeText ? "1" : "0", "SUBSPACE_UI_TEST_APPEARANCE": light ? "light" : "dark", "SUBSPACE_UI_TEST_REDUCE_MOTION": reducedMotion ? "1" : "0", "SUBSPACE_UI_TEST_REDUCE_TRANSPARENCY": reducedMotion ? "1" : "0"]
        let rates = ExchangeRates(rates: ["CAD": Decimal(135) / 100, "EUR": Decimal(9) / 10])
        app.launchEnvironment["SUBSPACE_UI_TEST_RATES"] = String(decoding: try JSONEncoder().encode(rates), as: UTF8.self)
        if populated {
            let start = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: .now), month: 1, day: 1)) ?? .now
            let intervals: [BillingInterval] = [.weekly, .monthly, .annual, .quarterly, .biweekly, .semiannual, .init(count: 10, unit: .day)]
            let currencies = ["CAD", "USD", "EUR"]
            let records = (0..<14).map { index in
                SubscriptionRecord(name: String(format: "Plan %02d", index + 1), amount: Decimal((index + 1) * 3), currency: currencies[index % currencies.count], interval: intervals[index % intervals.count], startDate: start, nextRenewal: Date.now.addingTimeInterval(Double(index + 1) * 86400), category: SubspaceCore.Category.allCases[index % SubspaceCore.Category.allCases.count], reminderDays: nil)
            }
            app.launchEnvironment["SUBSPACE_UI_TEST_BACKUP"] = String(decoding: try JSONEncoder().encode(Backup(subscriptions: records)), as: UTF8.self)
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Overview"].waitForExistence(timeout: 20))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func open(_ tab: String) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        XCTAssertTrue(button.isSelected, "Selected tab must remain visible: \(tab)")
    }
    private func assertNavigation() {
        for tab in tabs { XCTAssertTrue(app.tabBars.buttons[tab].isHittable, "Tab inaccessible: \(tab)") }
        let add = element("addSubscription")
        XCTAssertTrue(add.isHittable)
        XCTAssertFalse(add.frame.intersects(app.tabBars.firstMatch.frame), "Add must not overlap tab navigation")
    }
    private func revealAboveTabBar(_ id: String) {
        let item = element(id)
        for _ in 0..<24 {
            if item.exists && item.isHittable && item.frame.maxY <= app.tabBars.firstMatch.frame.minY + 2 { break }
            swipeUp()
        }
        XCTAssertTrue(item.exists && item.isHittable, "Bottom content must remain reachable: \(id)")
        XCTAssertLessThanOrEqual(item.frame.maxY, app.tabBars.firstMatch.frame.minY + 2, "Bottom content overlaps navigation: \(id)")
    }
    private func swipeUp() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.75)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.25)))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
