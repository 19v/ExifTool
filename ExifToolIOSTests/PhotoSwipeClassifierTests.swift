#if os(iOS)

import XCTest
@testable import ExifTool

final class PhotoSwipeClassifierTests: XCTestCase {
    func testClassifiesHorizontalSwipes() {
        XCTAssertEqual(
            PhotoSwipeClassifier.direction(
                translation: CGSize(width: 90, height: 10),
                predictedEndTranslation: CGSize(width: 120, height: 12)
            ),
            .previous
        )
        XCTAssertEqual(
            PhotoSwipeClassifier.direction(
                translation: CGSize(width: -90, height: 10),
                predictedEndTranslation: CGSize(width: -120, height: 12)
            ),
            .next
        )
    }

    func testIgnoresShortAndVerticalDrags() {
        XCTAssertNil(
            PhotoSwipeClassifier.direction(
                translation: CGSize(width: 30, height: 2),
                predictedEndTranslation: CGSize(width: 50, height: 3)
            )
        )
        XCTAssertNil(
            PhotoSwipeClassifier.direction(
                translation: CGSize(width: 80, height: 100),
                predictedEndTranslation: CGSize(width: 90, height: 140)
            )
        )
    }
}

#endif
