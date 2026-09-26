import XCTest

final class LyricsUI: XCTestCase {
    @MainActor func testRevealOnlyThenSeekAndHolds() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "pw.spoti.harness.immersive")
        app.launchArguments = ["-test", "0", "-song", "both", "-uitest", "1"]
        app.launch()
        let state = app.staticTexts["immersive-test-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        func expect(_ prefix: String, timeout: TimeInterval = 5) {
            if state.label.hasPrefix(prefix) { return }
            let p = NSPredicate { _, _ in state.label.hasPrefix(prefix) }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: p, object: state)], timeout: timeout), .completed)
        }
        func target() -> XCUICoordinate {
            let fields = state.label.split(separator: "|")
            XCTAssertEqual(fields.count, 6)
            return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: Double(fields[2])!, dy: Double(fields[3])!))
        }
        expect("immersive|0|")
        target().tap()
        expect("visible|0|")
        target().tap()
        expect("visible|1|")
        target().press(forDuration: 3)
        let metrics = state.label.split(separator: "|")
        XCTAssertEqual(metrics[4], "0", "chrome hid while the finger was down")
        XCTAssertGreaterThan(Double(metrics[5])!, 2.9, "long press was not delivered")
        expect("immersive|", timeout: 5)
        XCUIDevice.shared.press(.home)
        app.activate()
        expect("visible|")
        // Snapshot delivery can take longer than the idle interval after foregrounding.
        // A real touch restores the controls before opening their menu.
        target().tap()
        let options = app.buttons["Pronunciation and translation"]
        XCTAssertTrue(options.exists)
        options.tap()
        // Inverted expectation continuously checks the actual page while the menu stays open.
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in state.label.hasPrefix("immersive|") }, object: state)
        hidden.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()
        expect("immersive|")
        target().tap()
        app.swipeUp(velocity: .slow)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = .portrait
        expect("immersive|", timeout: 8)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.lifetime = .keepAlways
        add(image)
        app.terminate()
    }
}


final class SingControlsUI: XCTestCase {
    @MainActor func testVocalLevelDuringRecovery() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "pw.spoti.harness.immersive")
        app.launchArguments = ["-test", "0", "-song", "both", "-uitest", "1", "-sing-ui", "1", "-sing-recovery", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["immersive-test-state"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)).tap()
        let mic = app.buttons["sing.microphone"]
        mic.tap()
        XCTAssertTrue(app.staticTexts["Restoring Sing…"].waitForExistence(timeout: 3))
        let slider = app.descendants(matching: .any)["sing.vocalLevel"]
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.375)).tap()
        XCTAssertEqual(slider.value as? String, "70 percent")
        XCTAssertTrue(mic.isSelected)
        XCTAssertTrue(app.buttons["sing.level"].staticTexts["70%"].exists)
        XCTAssertFalse(app.alerts["Sing"].exists)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in mic.value as? String == "70 percent" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed)
        XCTAssertFalse(app.staticTexts["sing.status"].exists)
        app.terminate()
    }
    @MainActor func testReadyWhilePaused() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "pw.spoti.harness.immersive")
        app.launchArguments = ["-test", "0", "-song", "both", "-uitest", "1", "-sing-ui", "1", "-sing-paused", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["immersive-test-state"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)).tap()
        let mic = app.buttons["sing.microphone"]
        mic.tap()
        let ready = app.staticTexts["Ready when you play"]
        XCTAssertTrue(ready.waitForExistence(timeout: 3))
        let slider = app.descendants(matching: .any)["sing.vocalLevel"]
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.375)).tap()
        XCTAssertEqual(slider.value as? String, "70 percent")
        XCTAssertTrue(mic.isSelected)
        XCTAssertTrue(app.buttons["sing.level"].staticTexts["70%"].exists)
        app.buttons["Turn off Sing"].tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in mic.value as? String == "Off" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 3), .completed)
        app.terminate()
    }
    @MainActor func testIdleCapsuleAndImmersiveMicrophone() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "pw.spoti.harness.immersive")
        app.launchArguments = ["-test", "0", "-song", "both", "-uitest", "1", "-sing-ui", "1"]
        app.launch()
        let state = app.staticTexts["immersive-test-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)).tap()
        let mic = app.buttons["sing.microphone"]
        let slider = app.descendants(matching: .any)["sing.vocalLevel"]
        mic.tap()
        let active = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in mic.value as? String == "20 percent" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 3), .completed)
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !slider.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed, app.debugDescription)
        let immersive = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in state.label.hasPrefix("immersive|") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [immersive], timeout: 5), .completed)
        XCTAssertTrue(mic.exists && mic.isSelected)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Immersive lyrics with active Sing"; image.lifetime = .keepAlways; add(image)
        let seeks = state.label.split(separator: "|")[1]
        mic.tap()
        XCTAssertTrue(slider.exists, "The visible microphone responds to the first tap in immersive mode")
        XCTAssertTrue(state.label.hasPrefix("visible|"))
        XCTAssertEqual(state.label.split(separator: "|")[1], seeks)
        app.buttons["Turn off Sing"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in state.label.hasPrefix("immersive|") && !mic.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 6), .completed)
        app.terminate()
    }
    @MainActor func testCancelAndRestartDuringTransitions() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "pw.spoti.harness.immersive")
        app.launchArguments = ["-test", "0", "-song", "both", "-uitest", "1", "-sing-ui", "1", "-sing-slow", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["immersive-test-state"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)).tap()
        let mic = app.buttons["sing.microphone"]
        mic.tap()
        XCTAssertEqual(mic.value as? String, "Preparing Sing")
        XCTAssertEqual(app.staticTexts["sing.status"].label, "Preparing Sing…")
        XCTAssertTrue(mic.isEnabled)
        mic.tap() // Cancel without waiting for loading.
        XCTAssertEqual(mic.value as? String, "Turning Sing off")
        XCTAssertEqual(app.staticTexts["sing.status"].label, "Turning Sing off…")
        mic.tap() // Queue an immediate restart while the previous audio finishes.
        XCTAssertEqual(mic.value as? String, "Preparing Sing")
        app.buttons["Cancel Sing"].tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in mic.value as? String == "Off" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["sing.status"].exists)
        app.terminate()
    }
    @MainActor func testBlockedAttemptExplainsOnceWithoutRetryOrHidingControls() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "pw.spoti.harness.immersive")
        app.launchArguments = ["-test", "0", "-song", "both", "-uitest", "1", "-sing-ui", "1", "-sing-blocked", "1"]
        app.launch()
        let state = app.staticTexts["immersive-test-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)).tap()
        app.buttons["sing.microphone"].tap()
        XCTAssertTrue(app.alerts["Sing"].exists, "A blocked first attempt explains the restriction immediately")
        XCTAssertFalse(app.alerts.buttons["Try again"].exists, "Do not offer a retry that cannot start")
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in state.label.hasPrefix("immersive|") }, object: state)
        hidden.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.alerts["Sing"].exists)
        app.buttons["sing.microphone"].tap()
        app.alerts.buttons["Turn off Sing"].tap()
        let mic = app.buttons["sing.microphone"]
        let off = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in mic.value as? String == "Off" }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 3), .completed)
        XCTAssertFalse(app.alerts["Sing"].exists)
        app.terminate()
    }
    @MainActor func testPreparingVocalLevelAndImmersiveHold() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "pw.spoti.harness.immersive")
        app.launchArguments = ["-test", "0", "-song", "both", "-uitest", "1", "-sing-ui", "1"]
        app.launch()
        let state = app.staticTexts["immersive-test-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.4)).tap()
        let mic = app.buttons["sing.microphone"]
        // waitForExistence polls after a second; combined with XCTest's idle wait that can
        // outlast the production two-second chrome deadline. Query immediately after touch.
        XCTAssertTrue(mic.exists)
        mic.tap()
        let slider = app.descendants(matching: .any)["sing.vocalLevel"]
        XCTAssertTrue(slider.waitForExistence(timeout: 2))
        let active = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in mic.value as? String == "20 percent" }, object: mic)
        XCTAssertEqual(XCTWaiter.wait(for: [active], timeout: 3), .completed)
        XCTAssertTrue(state.label.hasPrefix("visible|"))
        mic.tap()
        XCTAssertEqual(slider.value as? String, "Original")
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let bottom = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.1))
        start.press(forDuration: 0.1, thenDragTo: bottom)
        XCTAssertEqual(slider.value as? String, "20 percent")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.1)))
        XCTAssertEqual(slider.value as? String, "Original")
        let geometry = app.staticTexts["sing-test-geometry"].label.split(separator: "|").map { Double($0)! }
        XCTAssertEqual(geometry[0], 144, accuracy: 0.5, "The capsule returns to its resting height after release")
        XCTAssertGreaterThan(geometry[1], 150, "Dragging stretches the capsule")
        XCTAssertLessThan(geometry[2], -2, "The glass follows an upward drag")
        XCTAssertGreaterThan(geometry[3], 2, "The glass follows a downward drag")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(slider.value as? String, "60 percent")
        XCTAssertTrue(mic.isSelected)
        XCTAssertFalse(app.staticTexts["sing.status"].exists)
        XCTAssertTrue(app.buttons["sing.level"].staticTexts["60%"].exists)
        mic.tap()
        XCTAssertEqual(slider.value as? String, "Original")
        XCTAssertFalse(mic.isSelected)
        XCTAssertTrue(app.buttons["sing.level"].staticTexts["100%"].exists)
        mic.tap()
        XCTAssertEqual(slider.value as? String, "60 percent", "Restores the reduced level chosen in this session")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            .press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        XCTAssertEqual(slider.value as? String, "96 percent", "A fast drag applies the final finger position")
        // A normal drag starting over the icon must also control vocals, without a long hold.
        let icon = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        icon.press(forDuration: 0.05, thenDragTo: icon.withOffset(CGVector(dx: 0, dy: -110)))
        XCTAssertEqual(slider.value as? String, "Original")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(slider.value as? String, "60 percent")
        let expanded = XCTAttachment(screenshot: app.screenshot()); expanded.name = "Vocal volume capsule"; expanded.lifetime = .keepAlways; add(expanded)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertFalse(slider.exists, "Touching outside collapses the capsule: \(app.debugDescription)")
        XCTAssertTrue(mic.isSelected, "Collapsed Sing remains selected while vocals are reduced")
        let collapsed = XCTAttachment(screenshot: app.screenshot()); collapsed.name = "Active collapsed microphone"; collapsed.lifetime = .keepAlways; add(collapsed)
        mic.press(forDuration: 0.7)
        XCTAssertTrue(slider.exists, "Holding the microphone reopens vocal volume")
        mic.tap()
        XCTAssertEqual(slider.value as? String, "Original")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertFalse(mic.isSelected, "Original vocals leave the collapsed control unselected")
        let original = XCTAttachment(screenshot: app.screenshot()); original.name = "Original collapsed microphone"; original.lifetime = .keepAlways; add(original)
        mic.press(forDuration: 0.7)
        app.buttons["Turn off Sing"].tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in mic.value as? String == "Off" && mic.isEnabled }, object: mic)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 3), .completed)
        let image = XCTAttachment(screenshot: app.screenshot()); image.lifetime = .keepAlways; add(image)
        app.terminate()
    }
}
