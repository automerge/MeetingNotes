import Foundation
import XCTest

final class MeetingNotesUITests: XCTestCase {
    override func setUpWithError() throws {
        // Method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation
        // - required for your tests before they run.
    }

    override func tearDownWithError() throws {
        // Method is called after the invocation of each test method in the class.
    }

    @available(macOS 14.0, iOS 17.0, *)
    func testAutomatedAccessibility() {
        // https://holyswift.app/xcode-15-new-feature-streamlined-accessibility-audits/
        let myApp = XCUIApplication()
        myApp.launch()

        do {
            // requires Xcode 15
            try myApp.performAccessibilityAudit()
        } catch {
            XCTFail("The automated accessibility audit fail because [\(error.localizedDescription)]")
        }
    }

//    func testLaunchPerformance() throws {
//        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
//            // This measures how long it takes to launch your application.
//            measure(metrics: [XCTApplicationLaunchMetric()]) {
//                XCUIApplication().launch()
//            }
//        }
//    }
}
