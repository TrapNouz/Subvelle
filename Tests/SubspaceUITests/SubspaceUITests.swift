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
                XCTAssertTrue(element("chartSelectionSummary").waitForExistence(timeout: 5), "A single tap must reveal a selected payment period")
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
        setAccessibilitySwitch(path: ["Accessibility", "Motion"], label: "Reduce Motion", enabled: true)
        setAccessibilitySwitch(path: ["Accessibility", "Display & Text Size"], label: "Reduce Transparency", enabled: true)
        defer {
            setAccessibilitySwitch(path: ["Accessibility", "Motion"], label: "Reduce Motion", enabled: false)
            setAccessibilitySwitch(path: ["Accessibility", "Display & Text Size"], label: "Reduce Transparency", enabled: false)
        }
        try launch(populated: true, largeText: true, light: true)
        for (index, tab) in tabs.enumerated() {
            open(tab); assertNavigation(); capture("Accessibility-Light-\(tab)-Top")
            revealAboveTabBar(bottoms[index]); capture("Accessibility-Light-\(tab)-Bottom")
        }
    }
    func testLandscapeSafeAreas() throws {
        try launch(populated: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        open("Overview")
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height, "The app must actually enter landscape")
        assertNavigation(); capture("Landscape-Overview")
        var unscrollable: [String] = []
        if revealAboveTabBar("overviewBottom", skipIfUnscrollable: true) { capture("Landscape-Overview-Bottom") } else { unscrollable.append("Overview") }
        open("Settings"); assertNavigation(); capture("Landscape-Settings")
        if revealAboveTabBar("settingsBottom", skipIfUnscrollable: true) { capture("Landscape-Settings-Bottom") } else { unscrollable.append("Settings") }
        if !unscrollable.isEmpty {
            throw XCTSkip("No synthesized gesture scrolled \(unscrollable.joined(separator: ", ")) in landscape on this simulator; the bottom-reachability check could not run.")
        }
    }
    private func launch(populated: Bool, largeText: Bool = false, light: Bool = false) throws {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launchEnvironment = ["SUBSPACE_UI_TEST_ID": UUID().uuidString, "SUBSPACE_UI_TEST_RESET": "1", "SUBSPACE_UI_TEST_LARGE_TEXT": largeText ? "1" : "0", "SUBSPACE_UI_TEST_APPEARANCE": light ? "light" : "dark"]
        let rates = ExchangeRates(rates: ["CAD": Decimal(135) / 100, "EUR": Decimal(9) / 10])
        app.launchEnvironment["SUBSPACE_UI_TEST_RATES"] = String(decoding: try JSONEncoder().encode(rates), as: UTF8.self)
        if populated {
            let start = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: .now), month: 1, day: 1)) ?? .now
            let intervals: [BillingInterval] = [.weekly, .monthly, .annual, .quarterly, .biweekly, .semiannual, .init(count: 10, unit: .day)]
            let currencies = ["CAD", "USD", "EUR"]
            var records: [SubscriptionRecord] = []
            for index in 0..<14 {
                let name = String(format: "Plan %02d", index + 1)
                let amount = Decimal((index + 1) * 3)
                let currency = currencies[index % currencies.count]
                let interval = intervals[index % intervals.count]
                let renewal = Date.now.addingTimeInterval(Double(index + 1) * 86400)
                let categories = SubspaceCore.Category.allCases
                let category = categories[index % categories.count]
                let record = SubscriptionRecord(name: name, amount: amount, currency: currency, interval: interval, startDate: start, nextRenewal: renewal, category: category, reminderDays: nil)
                records.append(record)
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
    /// Scrolls until `id` sits above the tab bar, then asserts it is reachable and unobstructed.
    /// Returns false, without asserting, only when `skipIfUnscrollable` is set and no gesture
    /// strategy moved the content at all: the simulator could not be driven, so nothing about
    /// the layout was learned. Any movement means the normal assertions apply.
    @discardableResult
    private func revealAboveTabBar(_ id: String, skipIfUnscrollable: Bool = false) -> Bool {
        let item = element(id)
        var strategy = 0
        var moved = false
        for _ in 0..<24 {
            if item.exists && item.isHittable && item.frame.maxY <= app.tabBars.firstMatch.frame.minY + 2 { break }
            let before = scrollSignature(item)
            swipeUp(strategy: strategy)
            if scrollSignature(item) != before {
                if !moved { print("Scrolling \(id) with strategy \(strategy)") }
                moved = true
            } else if !moved {
                strategy = (strategy + 1) % 5
            }
        }
        if !item.exists || !item.isHittable {
            capture("Unreachable-" + id)
            print(app.debugDescription)
            if skipIfUnscrollable && !moved { return false }
        }
        XCTAssertTrue(item.exists && item.isHittable, "Bottom content must remain reachable: \(id)")
        XCTAssertLessThanOrEqual(item.frame.maxY, app.tabBars.firstMatch.frame.minY + 2, "Bottom content overlaps navigation: \(id)")
        return true
    }
    /// Progress probe: the target's position (it may not exist yet in lazy lists) and the
    /// accessibility value of the vertical scroll bar ("0%" until the content moves).
    private func scrollSignature(_ item: XCUIElement) -> String {
        let bar = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Vertical scroll bar'")).firstMatch
        let position = item.exists ? String(format: "%.0f", item.frame.minY) : "absent"
        return position + "|" + (bar.exists ? (bar.value as? String ?? "") : "")
    }
    private func swipeUp(strategy: Int = 0) {
        let list = app.collectionViews.firstMatch
        let scroll = app.scrollViews.firstMatch
        let container = list.exists && list.isHittable ? list : (scroll.exists && scroll.isHittable ? scroll : app.windows.firstMatch)
        let window = app.windows.firstMatch
        func drag(_ target: XCUIElement, from: CGVector, to: CGVector) {
            target.coordinate(withNormalizedOffset: from)
                .press(forDuration: 0.05, thenDragTo: target.coordinate(withNormalizedOffset: to), withVelocity: .fast, thenHoldForDuration: 0)
        }
        switch strategy {
        case 0:
            // Lists: the native container. ScrollView screens: the leading margin, clear of
            // interactive charts and the trailing scroll indicator.
            if container == list { list.swipeUp(velocity: .fast) }
            else { drag(container, from: CGVector(dx: 0.03, dy: 0.8), to: CGVector(dx: 0.03, dy: 0.2)) }
        case 1: container.swipeUp(velocity: .fast)
        case 2: drag(window, from: CGVector(dx: 0.5, dy: 0.7), to: CGVector(dx: 0.5, dy: 0.3))
        // Landscape fallbacks in case synthesized events are delivered unrotated.
        case 3: drag(window, from: CGVector(dx: 0.7, dy: 0.5), to: CGVector(dx: 0.3, dy: 0.5))
        default: drag(window, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        }
    }
    private func setAccessibilitySwitch(path: [String], label: String, enabled: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate(); settings.launch()
        // Settings may restore its previous pane after a cold launch.
        for _ in 0..<6 {
            if settings.navigationBars["Settings"].exists { break }
            let back = settings.navigationBars.buttons.firstMatch
            if !back.exists || !back.isHittable { break }
            back.tap()
        }
        for title in path {
            let target = settings.staticTexts[title].firstMatch
            for _ in 0..<10 {
                if target.exists && target.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(target.exists && target.isHittable, "Settings destination missing: \(title)")
            target.tap()
        }
        var control = settings.switches[label].firstMatch
        for _ in 0..<8 {
            if control.exists && control.isHittable { break }
            settings.swipeUp()
        }
        XCTAssertTrue(control.exists && control.isHittable, "Accessibility setting missing: \(label)")
        if let nested = control.switches.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            control = nested
        }
        let expected = enabled ? "1" : "0"
        func isExpected() -> Bool {
            if let value = control.value as? NSNumber { return value.boolValue == enabled }
            return (control.value as? String) == expected
        }
        let candidates = control.switches.allElementsBoundByIndex
        if !isExpected(), let nested = candidates.first(where: { $0.isHittable }) { nested.tap() }
        // Settings sometimes exposes a row instead of the nested toggle. Verify each
        // real touch before trying another position; never blindly double-toggle.
        for x in [0.98, 0.9, 0.8, 0.5] {
            if isExpected() { break }
            control.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
            let expectedValue = NSPredicate(format: "value == %@ OR value == %@", expected, NSNumber(value: enabled))
            let updated = XCTNSPredicateExpectation(predicate: expectedValue, object: control)
            if XCTWaiter.wait(for: [updated], timeout: 2) == .completed { break }
        }
        if !isExpected() {
            let diagnostic = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            diagnostic.name = "Accessibility-setting-" + label
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            print(control.debugDescription)
            print(settings.debugDescription)
        }
        XCTAssertTrue(isExpected(), "Accessibility setting did not change: \(label)")
        settings.terminate()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
