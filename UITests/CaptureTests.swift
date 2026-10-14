import XCTest

/// Renders every deterministic fixture state and attaches one screenshot per
/// fixture, named exactly after the fixture. `scripts/capture.sh` exports these
/// attachments from the result bundle into `build/captures/frames/<name>.png`.
///
/// Contract with the app: `-fixture <name>` freezes time, loads sample data and
/// shows an element with accessibility identifier `machine.ready` once the
/// frame has settled.
final class CaptureTests: XCTestCase {

    static let readyTimeout: TimeInterval = 20
    static let settleDelay: TimeInterval = 0.5

    override func setUpWithError() throws {
        // One fixture failing must never stop the rest of the run.
        continueAfterFailure = true
    }

    // Methods are numbered so XCTest (alphabetical order) runs them in the
    // same order as the contact sheet.

    @MainActor func test01_dietIdle() { capture("diet-idle") }
    @MainActor func test02_dietHeld() { capture("diet-held") }
    @MainActor func test03_dietContact() { capture("diet-contact") }
    @MainActor func test04_dietSettled() { capture("diet-settled") }
    @MainActor func test05_prismHalf() { capture("prism-half") }
    @MainActor func test06_dietIntake() { capture("diet-intake") }
    @MainActor func test07_dietOverTarget() { capture("diet-over-target") }
    @MainActor func test08_dietEmpty() { capture("diet-empty") }
    @MainActor func test09_trainReady() { capture("train-ready") }
    @MainActor func test10_trainRest() { capture("train-rest") }
    @MainActor func test11_trainRestAdded() { capture("train-rest-added") }
    @MainActor func test12_bodyIdle() { capture("body-idle") }
    @MainActor func test12b_bodyScrub() { capture("body-scrub") }
    @MainActor func test12c_bodyFlex() { capture("body-flex") }
    @MainActor func test13_a11yXXL() {
        // The app renders this fixture at accessibility XXXL text; the system
        // launch argument makes sure Dynamic Type agrees.
        capture("a11y-xxl", extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])
    }

    // Comparison for Wei: the same frame in MONO.
    @MainActor func test15_dietIdleMono() { capture("diet-idle", as: "diet-idle-mono", extraArguments: ["-skin", "mono"]) }

    @MainActor
    private func capture(_ fixture: String, as name: String? = nil, extraArguments: [String] = []) {
        let fixtureName = fixture
        let fixture = name ?? fixture
        let app = XCUIApplication()
        app.launchArguments = ["-fixture", fixtureName] + extraArguments
        app.launch()

        let ready = app.descendants(matching: .any)["machine.ready"].firstMatch
        let isReady = ready.waitForExistence(timeout: Self.readyTimeout)
        if isReady {
            Thread.sleep(forTimeInterval: Self.settleDelay)
            attachScreenshot(named: fixture)
        } else {
            XCTFail("Fixture '\(fixture)': element 'machine.ready' did not appear within \(Int(Self.readyTimeout)) s. The app must show it once the fixture frame is settled.")
            // Keep what the screen showed so the failure can be diagnosed
            // without a Mac.
            attachScreenshot(named: "\(fixture)-NOT-READY")
        }
        app.terminate()
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
