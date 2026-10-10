import XCTest

final class RelayPadUITests: XCTestCase {
    func testTextBoxEditingAndDraftRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network"]
        app.launch()
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 15))
        app.buttons["relay.newPaper"].tap(); app.buttons["横向画布"].tap()
        XCTAssertTrue(app.buttons["relay.textTool"].waitForExistence(timeout: 10))
        app.buttons["relay.textTool"].tap()
        let canvas = app.otherElements["relay.canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
        let input = app.textViews["relay.textInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.typeText("PPT Review\n2026 中文标注")
        input.typeText("!")
        XCTAssertTrue(app.buttons["relay.undo"].isEnabled)
        app.buttons["relay.undo"].tap()
        XCTAssertFalse((input.value as? String)?.hasSuffix("!") == true)
        app.buttons["relay.redo"].tap()
        XCTAssertTrue((input.value as? String)?.hasSuffix("!") == true)
        XCTAssertTrue(app.buttons["relay.finishText"].exists)
        let typing = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); typing.name = "Native text keyboard"; typing.lifetime = .keepAlways; add(typing)
        app.buttons["relay.finishText"].tap()
        XCTAssertTrue(app.buttons["Pen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["relay.undo"].isEnabled)
        app.buttons["relay.undo"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "relay.textBox.")).count, 0)
        app.buttons["relay.redo"].tap()
        app.buttons["relay.back"].tap()
        XCTAssertTrue(app.buttons["relay.history"].waitForExistence(timeout: 5))
        app.buttons["relay.history"].tap()
        app.buttons.containing(.staticText, identifier: "白纸画作").firstMatch.tap()
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 5))
        app.buttons["relay.continue"].tap()
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "relay.textBox.")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertTrue(box.label.contains("PPT Review"))
        box.doubleTap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue((input.value as? String)?.contains("中文标注") == true)
        input.typeText(" edited")
        app.buttons["relay.finishText"].tap()
        let result = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); result.name = "Restored editable text"; result.lifetime = .keepAlways; add(result)
    }
    func testKeyboardAvoidsTextAndRestoresViewport() throws {
        continueAfterFailure = false
        let orientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = orientation }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network"]
        app.launch()
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 15))
        app.buttons["relay.newPaper"].tap(); app.buttons["竖向画布"].tap()
        app.buttons["relay.textTool"].tap()
        app.otherElements["relay.canvas"].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8)).tap()
        let input = app.textViews["relay.textInput"], keyboard = app.keyboards.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10)); input.typeText("Bottom notes")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 3)
        let editingY = input.frame.minY
        app.buttons["relay.finishText"].tap()
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "relay.textBox.")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(box.frame.minY, editingY + 30, "Keyboard dismissal should restore the prior view")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Viewport restored after bottom text input"; shot.lifetime = .keepAlways; add(shot)
    }
    func testTextStylesMoveResizeAndDeleteUndo() throws {
        continueAfterFailure = false
        let orientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = orientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network", "--relay-ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 15))
        app.buttons["relay.newPaper"].tap(); app.buttons["横向画布"].tap()
        app.buttons["relay.textTool"].tap()
        let canvas = app.otherElements["relay.canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4)).tap()
        let input = app.textViews["relay.textInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.typeText("Slide notes: editable text wraps automatically.")
        app.buttons["relay.finishText"].tap()
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "relay.textBox.")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 5)); box.tap()
        let before = box.frame
        box.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 0.15,
            thenDragTo: box.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).withOffset(CGVector(dx: 50, dy: 25)))
        XCTAssertGreaterThan(box.frame.minX, before.minX + 20)
        let width = box.frame.width
        box.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).press(forDuration: 0.15,
            thenDragTo: box.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -80, dy: 0)))
        XCTAssertLessThan(box.frame.width, width - 30)
        app.buttons["relay.textBold"].tap(); app.buttons["relay.textBackground"].tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Text styles dark large type landscape"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["relay.deleteText"].tap()
        XCTAssertFalse(box.exists)
        app.buttons["relay.undo"].tap(); XCTAssertTrue(box.exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["relay.complete"].waitForExistence(timeout: 5))
    }
    func testPhysicalTextAndInkAutomaticallyReturn() throws {
        guard ProcessInfo.processInfo.environment["RELAY_PHYSICAL_E2E"] == "1" else { throw XCTSkip("Requires paired updated Mac") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments += ["--uitest-open-relay"]; app.launch()
        if app.buttons["结束共同编辑"].waitForExistence(timeout: 3) {
            app.buttons["结束共同编辑"].tap()
            XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 30))
        }
        if app.buttons["relay.back"].waitForExistence(timeout: 3) { app.buttons["relay.back"].tap() }
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 15))
        app.buttons["relay.newPaper"].tap(); app.buttons["横向画布"].tap()
        let connected = app.buttons["relay.connection"]
        expectation(for: NSPredicate { _, _ in connected.label.contains("已连接") }, evaluatedWith: connected)
        waitForExpectations(timeout: 30)
        app.buttons["relay.canvasOptions"].tap(); app.buttons["共同编辑"].tap()
        XCTAssertTrue(app.buttons["结束共同编辑"].waitForExistence(timeout: 15))
        enableFinger(app)
        let canvas = app.otherElements["relay.canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).press(forDuration: 0.1,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.7)))
        app.buttons["relay.textTool"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        let input = app.textViews["relay.textInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.typeText("Picelf PPT\n中文标注 + Apple 听写")
        // The complete stable text layer is acknowledged while the keyboard is still open.
        XCTAssertTrue(app.staticTexts["已复制，直接粘贴 · 共同编辑中"].waitForExistence(timeout: 30))
        XCTAssertTrue(input.exists)
        app.buttons["relay.finishText"].tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Physical live text and ink copied"; shot.lifetime = .keepAlways; add(shot)
        print("RELAY_TEXT_LIVE_COPIED")
        app.buttons["结束共同编辑"].tap()
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 30))
        app.buttons["relay.continue"].tap()
        XCTAssertTrue(app.buttons["结束共同编辑"].waitForExistence(timeout: 15))
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "relay.textBox.")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 5)); XCTAssertTrue(box.label.contains("中文标注"))
        box.doubleTap(); XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText(" · v2")
        XCTAssertTrue(app.staticTexts["已复制，直接粘贴 · 共同编辑中"].waitForExistence(timeout: 30))
        app.buttons["结束共同编辑"].tap()
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 30))
        print("RELAY_TEXT_INHERITANCE_COPIED")
        app.terminate(); app.launch()
        if app.buttons["relay.back"].waitForExistence(timeout: 3) { app.buttons["relay.back"].tap() }
        app.buttons["relay.history"].tap()
        app.buttons.containing(.staticText, identifier: "白纸画作").firstMatch.tap()
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 5))
        app.buttons["relay.continue"].tap()
        XCTAssertTrue(box.waitForExistence(timeout: 10)); XCTAssertTrue(box.label.contains("v2"))
        XCTAssertTrue(app.staticTexts["已复制，直接粘贴 · 共同编辑中"].waitForExistence(timeout: 30))
        app.buttons["结束共同编辑"].tap()
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 30))
        print("RELAY_TEXT_RESTART_RESTORED")
    }
    func testPhysicalOneSidedTrustRecovery() throws {
        guard ProcessInfo.processInfo.environment["RELAY_PHYSICAL_E2E"] == "1" else { throw XCTSkip("Requires Mac with existing trust; operator compares displayed codes") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments += ["--uitest-open-relay"]; app.launch()
        let code = app.staticTexts["relay.pairingCode"]
        // The iPad has forgotten the Mac; keep the Mac's existing trust intact.
        if !code.waitForExistence(timeout: 5) {
            if app.buttons["relay.retryPairing"].exists { app.buttons["relay.retryPairing"].tap() }
            if !code.waitForExistence(timeout: 5) {
                if app.buttons["relay.back"].exists { app.buttons["relay.back"].tap() }
                app.buttons["relay.connection"].tap()
                if app.buttons["解除配对"].exists { app.buttons["解除配对"].tap() }
                app.buttons["完成"].tap()
                if app.buttons["relay.connectDiscovered"].waitForExistence(timeout: 5) { app.buttons["relay.connectDiscovered"].tap() }
            }
        }
        XCTAssertTrue(code.waitForExistence(timeout: 40))
        print("PAIRING_ONE_SIDED_CODE: \(code.label)")
        // Operator compares the Mac's delayed code card during this interval.
        // Passing the former 20-second deadline verifies that checking codes
        // no longer tears down an otherwise healthy authenticated connection.
        let prematureFailure = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["relay.retryPairing"].exists }, object: nil)
        prematureFailure.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [prematureFailure], timeout: 30), .completed)
        XCTAssertTrue(code.exists)
        XCTAssertTrue(app.staticTexts["对方已确认，请核对配对码"].exists)
        app.buttons["relay.confirmPairing"].tap()
        let badge = app.buttons["relay.connection"]
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in badge.label.contains("已连接") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 20), .completed)
        print("PAIRING_ONE_SIDED_RECOVERED")
    }
    private func enableFinger(_ app: XCUIApplication) {
        app.buttons["relay.canvasOptions"].tap()
        let enable = app.buttons["开启手指绘画"]
        if enable.waitForExistence(timeout: 2) { enable.tap() }
        else { app.buttons["relay.canvasOptions"].tap() }
        // PencilKit remembers the user's last tool, including the eraser.
        // A drawing regression must explicitly select ink before its gesture.
        let pen = app.buttons["Pen"]
        XCTAssertTrue(pen.waitForExistence(timeout: 5))
        if !pen.isSelected { pen.tap() }
    }
    private func disableFinger(_ app: XCUIApplication) {
        app.buttons["relay.canvasOptions"].tap()
        let disable = app.buttons["关闭手指绘画"]
        if disable.waitForExistence(timeout: 2) { disable.tap() }
        else { app.buttons["relay.canvasOptions"].tap() }
    }
    func testPhysicalContinueSharedLayers() throws {
        guard ProcessInfo.processInfo.environment["RELAY_PHYSICAL_E2E"] == "1" else { throw XCTSkip("Requires an existing shared work with Mac arrow and Pencil ink") }
        let app = XCUIApplication(); app.launchArguments += ["--uitest-open-relay"]; app.launch()
        if app.buttons["结束共同编辑"].waitForExistence(timeout: 10) { app.buttons["结束共同编辑"].tap() }
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 30))
        app.buttons["relay.continue"].tap()
        XCTAssertTrue(app.buttons["结束共同编辑"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["已复制，直接粘贴 · 共同编辑中"].waitForExistence(timeout: 30))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "iPad continues both editable layers"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["结束共同编辑"].tap()
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 30))
    }
    func testPhysicalLiveCollaboration() throws {
        guard ProcessInfo.processInfo.environment["RELAY_PHYSICAL_E2E"] == "1" else { throw XCTSkip("Requires paired Mac operator") }
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay"]
        app.launch()
        if app.buttons["relay.back"].waitForExistence(timeout: 3) { app.buttons["relay.back"].tap() }
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 15))
        app.buttons["relay.newPaper"].tap(); app.buttons["横向画布"].tap()
        XCTAssertTrue(app.buttons["relay.complete"].waitForExistence(timeout: 15))
        let connected = app.buttons["relay.connection"]
        expectation(for: NSPredicate { _, _ in connected.label.contains("已连接") }, evaluatedWith: connected)
        waitForExpectations(timeout: 30)
        app.buttons["relay.canvasOptions"].tap(); app.buttons["共同编辑"].tap()
        XCTAssertTrue(app.buttons["结束共同编辑"].waitForExistence(timeout: 15))
        enableFinger(app)
        let canvas = app.otherElements["relay.canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        let copied = app.staticTexts["已复制，直接粘贴 · 共同编辑中"]
        XCTAssertTrue(copied.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["结束共同编辑"].exists)
        print("RELAY_LIVE_READY_FOR_MAC_EDIT")
        // Wait for the operator's actual clipboard action rather than a fixed delay.
        // Before copying text, the operator adds an arrow and inspects the full PNG.
        XCTAssertTrue(app.staticTexts["共同编辑中 · 自动复制已暂停"].waitForExistence(timeout: 120))
        let both = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); both.name = "Live Mac annotation and iPad ink"; both.lifetime = .keepAlways; add(both)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.7)))
        XCTAssertTrue(app.staticTexts["共同编辑中 · 自动复制已暂停"].waitForExistence(timeout: 20))
        app.buttons["relay.undo"].tap()
        disableFinger(app)
        app.buttons["结束共同编辑"].tap()
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 30))
        XCTAssertTrue(canvas.exists)
        XCTAssertTrue(app.staticTexts["已保存 · 自动复制已暂停"].exists)
        let ended = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); ended.name = "Live session ended without leaving canvas"; ended.lifetime = .keepAlways; add(ended)
    }
    func testPhysicalIPadOriginRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["RELAY_PHYSICAL_E2E"] == "1" else {
            throw XCTSkip("Opt-in: requires a previously paired Mac")
        }
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay"]
        app.launch()
        if app.buttons["relay.back"].waitForExistence(timeout: 2) { app.buttons["relay.back"].tap() }
        let paper = app.buttons["relay.newPaper"]
        XCTAssertTrue(paper.waitForExistence(timeout: 15))
        paper.tap()
        app.buttons["横向画布"].tap()
        let complete = app.buttons["relay.complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 15))
        enableFinger(app)
        let canvas = app.otherElements["relay.canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["relay.undo"])
        waitForExpectations(timeout: 10)
        disableFinger(app)
        let drawing = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        drawing.name = "Physical iPad originated white paper"; drawing.lifetime = .keepAlways; add(drawing)
        complete.tap()
        XCTAssertTrue(app.staticTexts["已到 Mac，直接粘贴"].waitForExistence(timeout: 30))
        XCTAssertTrue(canvas.exists)
        XCTAssertTrue(app.buttons["relay.continue"].exists)
        XCTAssertFalse(app.buttons["relay.complete"].exists)
    }
    // Run explicitly with a Mac operator comparing both displayed codes before
    // confirming on Mac. This uses the real network and the production pairing.
    func testPhysicalMacRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["RELAY_PHYSICAL_E2E"] == "1" else {
            throw XCTSkip("Opt-in: requires connected physical iPad and Mac pairing operator")
        }
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay"]
        app.launch()
        addUIInterruptionMonitor(withDescription: "Local network permission") { alert in
            for label in ["允许", "Allow", "好", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        if app.buttons["relay.back"].waitForExistence(timeout: 2) { app.buttons["relay.back"].tap() }
        app.tap() // Trigger the interruption handler if first-run network consent is showing.
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '配对码 '")).firstMatch
        let connected = app.buttons["relay.connection"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in code.exists || (connected.exists && connected.label.contains("已连接")) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed)
        if code.exists {
            print("RELAY_DEVICE_PAIRING: \(code.label)")
            let confirmation = app.buttons["Mac 已确认，配对"]
            XCTAssertTrue(confirmation.waitForExistence(timeout: 120), "Compare the logged iPad code with Mac and confirm on Mac")
            confirmation.tap()
        }
        let complete = app.buttons["relay.complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 120), "Send a test image from Mac")
        enableFinger(app)
        let canvas = app.otherElements["relay.canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["relay.undo"])
        waitForExpectations(timeout: 10)
        disableFinger(app)
        let drawing = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        drawing.name = "Physical iPad ink before return"; drawing.lifetime = .keepAlways; add(drawing)
        print("RELAY_READY_FOR_SECOND_IMAGE")
        // The operator sends another image while this canvas is still active.
        sleep(15)
        complete.tap()
        XCTAssertTrue(app.staticTexts["已到 Mac，直接粘贴"].waitForExistence(timeout: 30))
        XCTAssertTrue(canvas.exists)
        XCTAssertTrue(app.buttons["relay.continue"].exists)
        XCTAssertFalse(app.buttons["relay.complete"].exists)
        let receipt = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        receipt.name = "Physical iPad received Mac clipboard acknowledgement"; receipt.lifetime = .keepAlways; add(receipt)
        XCTAssertTrue(app.buttons["relay.next"].waitForExistence(timeout: 30), "Send a second image from Mac")
        XCTAssertTrue(app.buttons["relay.continue"].exists, "New arrivals must not replace the result")
        app.buttons["relay.next"].tap()
        XCTAssertTrue(app.buttons["relay.complete"].waitForExistence(timeout: 10))
        app.buttons["relay.back"].tap()
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 10))
    }
    func testDraftResumeDarkLargeTextAndRotation() throws {
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network", "--relay-ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 15))
        app.buttons["relay.newPaper"].tap(); app.buttons["竖向画布"].tap()
        XCTAssertTrue(app.buttons["relay.complete"].waitForExistence(timeout: 10))
        enableFinger(app)
        let canvas = app.otherElements["relay.canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["relay.undo"])
        waitForExpectations(timeout: 5)
        disableFinger(app)
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); portrait.name = "Dark large text portrait canvas"; portrait.lifetime = .keepAlways; add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height && app.buttons["relay.complete"].isHittable }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); landscape.name = "Dark large text landscape canvas"; landscape.lifetime = .keepAlways; add(landscape)
        app.buttons["relay.back"].tap()
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 10))
        app.buttons["relay.history"].tap()
        app.buttons.containing(.staticText, identifier: "白纸画作").firstMatch.tap()
        XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 5))
        app.buttons["relay.continue"].tap()
        XCTAssertTrue(app.buttons["relay.complete"].waitForExistence(timeout: 5))
        app.buttons["relay.complete"].tap()
        XCTAssertTrue(app.staticTexts["画作已保存，等待重连回传"].waitForExistence(timeout: 15))
    }
    func testPhysicalAutomaticPairingFromEitherDevice() throws {
        guard ProcessInfo.processInfo.environment["RELAY_PHYSICAL_E2E"] == "1" else { throw XCTSkip("Requires paired Mac operator") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments += ["--uitest-open-relay"]; app.launch()
        for round in 0..<2 {
            if app.buttons["relay.cancelPairing"].exists { app.buttons["relay.cancelPairing"].tap() }
            if app.buttons["relay.back"].exists { app.buttons["relay.back"].tap() }
            app.buttons["relay.connection"].tap()
            if app.buttons["解除配对"].waitForExistence(timeout: 3) { app.buttons["解除配对"].tap() }
            app.buttons["完成"].tap()
            print("PAIRING_OPERATOR_FORGET_MAC round=\(round)")
            // Mac operator forgets its previous trust before initiating either side.
            let code = app.staticTexts["relay.pairingCode"]
            if round == 0 {
                // Operator sends an invitation from Mac; no iPad connection tap.
                XCTAssertTrue(code.waitForExistence(timeout: 120))
            } else {
                // Give the Mac operator time to forget its trust and close/collapse preview.
                sleep(20)
                // Clearing trust on the second device can interrupt an automatic
                // reconnect from the still-trusted first device. Exercise recovery.
                let recovery = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    app.buttons["relay.retryPairing"].exists || app.buttons["relay.connectDiscovered"].exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [recovery], timeout: 45), .completed)
                if app.buttons["relay.retryPairing"].exists {
                    app.buttons["relay.retryPairing"].tap()
                } else {
                    XCTAssertTrue(app.buttons["relay.connectDiscovered"].waitForExistence(timeout: 30))
                    app.buttons["relay.connectDiscovered"].tap()
                }
                XCTAssertTrue(code.waitForExistence(timeout: 30))
            }
            print("PAIRING_ACTUAL_CODE round=\(round): \(code.label)")
            XCTAssertTrue(app.buttons["relay.confirmPairing"].isHittable)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Real automatic pairing round \(round)"; shot.lifetime = .keepAlways; add(shot)
            XCTAssertTrue(app.staticTexts["对方已确认，请核对配对码"].waitForExistence(timeout: 120))
            app.buttons["relay.confirmPairing"].tap()
            let badge = app.buttons["relay.connection"]
            let connected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in badge.label.contains("已连接") }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [connected], timeout: 20), .completed)
            XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 10))
            print("PAIRING_REAL_CONNECTED round=\(round)")
        }
    }
    func testPairingCardAppearsWithoutConnectionButton() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network", "--relay-ui-pairing"]
        app.launch()
        let confirm = app.buttons["relay.confirmPairing"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(app.staticTexts["relay.pairingCode"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        XCTAssertTrue(confirm.exists, "Tapping outside must not cancel pairing")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Automatic central pairing card"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["relay.cancelPairing"].tap()
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.exists)
    }
    func testPairingRequestWaitsForModalAndFitsLargeText() throws {
        let original = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = original }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network", "--relay-ui-pairing", "--relay-ui-pairing-delayed", "--relay-ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["relay.history"].tap()
        XCTAssertTrue(app.navigationBars["最近记录"].waitForExistence(timeout: 5))
        // Request arrives while the history sheet owns presentation.
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["relay.confirmPairing"].exists }, object: nil)
        unexpected.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: 4), .completed)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["relay.confirmPairing"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Deferred pairing large text landscape"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<4 where !app.buttons["relay.cancelPairing"].isHittable {
            app.scrollViews.containing(.button, identifier: "relay.cancelPairing").firstMatch.swipeUp()
        }
        XCTAssertTrue(app.buttons["relay.cancelPairing"].isHittable)
        app.buttons["relay.cancelPairing"].tap()
    }
    func testNewCanvasOrientationChoicesStayVisible() throws {
        verifyPaperChoices(largeText: false)
    }
    func testNewCanvasOrientationChoicesWithLargeText() throws {
        verifyPaperChoices(largeText: true)
    }
    private func verifyPaperChoices(largeText: Bool) {
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network"]
        if largeText {
            app.launchArguments += ["--relay-ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        for (index, orientation) in [UIDeviceOrientation.landscapeLeft, .portrait].enumerated() {
            XCUIDevice.shared.orientation = orientation
            let paper = app.buttons["relay.newPaper"]
            XCTAssertTrue(paper.waitForExistence(timeout: 10))
            let geometry = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (index == 0 ? app.frame.width > app.frame.height : app.frame.height > app.frame.width) && paper.isHittable
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [geometry], timeout: 5), .completed)
            let tabBarFrame = app.tabBars.firstMatch.frame
            paper.tap()
            let horizontal = app.buttons["横向画布"], vertical = app.buttons["竖向画布"]
            XCTAssertTrue(horizontal.waitForExistence(timeout: 5))
            for option in [horizontal, vertical] {
                XCTAssertTrue(option.isHittable)
                XCTAssertGreaterThanOrEqual(option.frame.height, 44)
                XCTAssertTrue(app.frame.contains(option.frame), "The full choice must be onscreen")
                XCTAssertFalse(option.frame.intersects(tabBarFrame), "Choices must not be clipped into the tab bar")
            }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Canvas direction choices \(index) largeText=\(largeText)"; shot.lifetime = .keepAlways; add(shot)
            // Dismissing and opening again must not create a canvas by accident.
            app.buttons["取消"].tap()
            XCTAssertTrue(paper.waitForExistence(timeout: 5))
            paper.tap()
            (index == 0 ? horizontal : vertical).tap()
            XCTAssertTrue(app.buttons["relay.complete"].waitForExistence(timeout: 10))
            app.buttons["relay.back"].tap()
        }
    }
    func testReturningHomeDismissesDrawingTools() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network"]
        app.launch()
        XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 15))
        app.buttons["relay.newPaper"].tap(); app.buttons["横向画布"].tap()
        for cycle in 0..<2 {
            XCTAssertTrue(app.buttons["relay.complete"].waitForExistence(timeout: 10))
            enableFinger(app)
            let canvas = app.otherElements["relay.canvas"]
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3))
                .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)))
            XCTAssertTrue(app.buttons["relay.undo"].isEnabled)
            disableFinger(app)
            app.buttons["relay.back"].tap()
            XCTAssertTrue(app.buttons["relay.newPaper"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["已保留草稿"].exists)
            XCTAssertFalse(app.staticTexts["Mac 已复制"].exists)
            XCTAssertFalse(canvas.exists)
            let tabs = app.tabBars.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 5))
            XCTAssertTrue(tabs.buttons["Settings"].isHittable)
            let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            home.name = "Home after drawing \(cycle)"; home.lifetime = .keepAlways; add(home)
            if cycle == 0 {
                tabs.buttons["Settings"].tap()
                tabs.buttons["接力画板"].tap()
                app.buttons["relay.history"].tap()
                app.buttons.containing(.staticText, identifier: "已保留草稿").firstMatch.tap()
                XCTAssertTrue(app.buttons["relay.continue"].waitForExistence(timeout: 5))
                app.buttons["relay.continue"].tap()
            }
        }
    }
    func testBlankCanvasCanDrawAndQueueReturnOffline() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uitest-open-relay", "--relay-ui-isolated", "--relay-ui-no-network"]
        app.launch()
        if app.buttons["relay.back"].waitForExistence(timeout: 2) { app.buttons["relay.back"].tap() }
        let paper = app.buttons["relay.newPaper"]
        XCTAssertTrue(paper.waitForExistence(timeout: 15))
        paper.tap()
        app.buttons["横向画布"].tap()
        let complete = app.buttons["relay.complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        let canvas = app.otherElements["relay.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        enableFinger(app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)))
        let undo = app.buttons["relay.undo"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: undo)
        waitForExpectations(timeout: 5)
        disableFinger(app)
        let drawing = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        drawing.name = "Relay iPad drawing"; drawing.lifetime = .keepAlways; add(drawing)
        complete.tap()
        XCTAssertTrue(app.staticTexts["画作已保存，等待重连回传"].waitForExistence(timeout: 15))
        XCTAssertTrue(canvas.exists, "Sending must retain the canvas")
        XCTAssertFalse(paper.exists, "Sending must not return to the home screen")
        app.buttons["relay.back"].tap()
        XCTAssertTrue(paper.waitForExistence(timeout: 10))
        app.buttons["relay.history"].tap()
        XCTAssertTrue(app.staticTexts["等待 Mac 复制确认"].waitForExistence(timeout: 5))
        let history = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        history.name = "Relay pending return"; history.lifetime = .keepAlways; add(history)
        app.terminate()
    }
}
