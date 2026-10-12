import XCTest

/// Drives the live machine (`-demo`: sample data, real time and physics) through
/// the main DIET and TRAIN interactions. `scripts/capture.sh` records the
/// simulator screen while this runs (build/captures/gestures.mp4) and exports a
/// screenshot attachment after each step (`gesture-NN-...`).
final class GestureTests: XCTestCase {

    static let readyTimeout: TimeInterval = 20
    static let elementTimeout: TimeInterval = 10

    override func setUpWithError() throws {
        // A missing element fails the test but the remaining steps still run,
        // so the video and screenshots show as much as possible.
        continueAfterFailure = true
    }

    @MainActor
    func testDietGestures() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        guard element("machine.ready", in: app).waitForExistence(timeout: Self.readyTimeout) else {
            XCTFail("Demo launch: element 'machine.ready' did not appear within \(Int(Self.readyTimeout)) s.")
            attachScreenshot(named: "gesture-01-NOT-READY")
            return
        }
        pause(1.0)
        attachScreenshot(named: "gesture-01-ready")

        // Step 2: lift the 250 kcal weight and set it down on the deck.
        let block250 = element("rail.block.250", in: app)
        let landing = element("deck.landing", in: app)
        if require(block250, "rail.block.250"), require(landing, "deck.landing") {
            let start = block250.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = landing.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.5, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        pause(2.0)
        attachScreenshot(named: "gesture-02-drop-250")

        // Step 3: lift the 100 kcal weight and release it far from the deck (cancel).
        let block100 = element("rail.block.100", in: app)
        if require(block100, "rail.block.100") {
            let start = block100.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            // Release on the half of the screen the deck is not on.
            let screen = app.frame
            let deckMidY = landing.exists ? landing.frame.midY : screen.maxY
            let farDy: CGFloat = deckMidY > screen.midY ? 0.12 : 0.88
            let far = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: farDy))
            start.press(forDuration: 0.5, thenDragTo: far, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        pause(2.0)
        attachScreenshot(named: "gesture-03-cancel-100")

        // Step 4: rotate to TRAIN.
        tap("face.next", in: app)
        pause(2.0)
        attachScreenshot(named: "gesture-04-train")

        // Step 5: SET DONE fires the piston and starts the rest.
        tap("train.setDone", in: app)
        pause(2.0)
        attachScreenshot(named: "gesture-05-set-done")

        // Step 6: add rest time.
        tap("train.addTime", in: app)
        pause(1.5)
        attachScreenshot(named: "gesture-06-add-time")

        // Step 7: rotate to BODY.
        tap("face.next", in: app)
        pause(2.0)
        attachScreenshot(named: "gesture-07-body")

        // Step 8: rotate once more, back to DIET.
        tap("face.next", in: app)
        pause(2.0)
        attachScreenshot(named: "gesture-08-diet")

        app.terminate()
    }

    // MARK: - Helpers

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Waits for the element; records a failure (without stopping) if it never appears.
    @MainActor
    private func require(_ element: XCUIElement, _ identifier: String) -> Bool {
        if element.waitForExistence(timeout: Self.elementTimeout) { return true }
        XCTFail("Element '\(identifier)' did not appear within \(Int(Self.elementTimeout)) s.")
        return false
    }

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let target = element(identifier, in: app)
        guard require(target, identifier) else { return }
        if target.isHittable {
            target.tap()
        } else {
            // Accessibility-only controls may report as not hittable; tap
            // their centre directly instead of failing the hittability check.
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
