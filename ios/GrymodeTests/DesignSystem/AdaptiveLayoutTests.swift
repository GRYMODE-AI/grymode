import XCTest

@testable import Grymode

final class AdaptiveLayoutTests: XCTestCase {
    func testWidthClassBreakpoints() {
        XCTAssertEqual(AdaptiveLayout(containerWidth: 320).widthClass, .compact)  // iPhone SE / Slide Over
        XCTAssertEqual(AdaptiveLayout(containerWidth: 430).widthClass, .compact)  // Large iPhone portrait
        XCTAssertEqual(AdaptiveLayout(containerWidth: 599).widthClass, .compact)
        XCTAssertEqual(AdaptiveLayout(containerWidth: 600).widthClass, .regular)
        XCTAssertEqual(AdaptiveLayout(containerWidth: 834).widthClass, .regular)  // iPad portrait detail
        XCTAssertEqual(AdaptiveLayout(containerWidth: 960).widthClass, .expanded)
        XCTAssertEqual(AdaptiveLayout(containerWidth: 1366).widthClass, .expanded)  // iPad Pro landscape
        XCTAssertEqual(AdaptiveLayout(containerWidth: -10).containerWidth, 0)
    }

    func testReadableWidthIsCappedOnlyWhenThereIsRoom() {
        XCTAssertEqual(AdaptiveLayout(containerWidth: 390).readableContentWidth, .infinity)
        XCTAssertEqual(AdaptiveLayout(containerWidth: 800).readableContentWidth, 680)
        XCTAssertEqual(AdaptiveLayout(containerWidth: 1300).readableContentWidth, 760)
    }

    func testMarginsGrowWithWidth() {
        let margins = [320, 800, 1300].map { AdaptiveLayout(containerWidth: CGFloat($0)).horizontalMargin }
        XCTAssertEqual(margins, margins.sorted())
        XCTAssertEqual(Set(margins).count, 3)
    }

    func testGridColumnsAdaptAndStayWithinBounds() {
        XCTAssertEqual(AdaptiveLayout(containerWidth: 320).gridColumnCount, 2)
        XCTAssertEqual(AdaptiveLayout(containerWidth: 100).gridColumnCount, 2)
        XCTAssertGreaterThanOrEqual(AdaptiveLayout(containerWidth: 834).gridColumnCount, 4)
        XCTAssertEqual(AdaptiveLayout(containerWidth: 5000).gridColumnCount, 6)
    }

    func testSideBySideOnlyBeyondCompact() {
        XCTAssertFalse(AdaptiveLayout(containerWidth: 430).prefersSideBySide)
        XCTAssertTrue(AdaptiveLayout(containerWidth: 700).prefersSideBySide)
    }
}
