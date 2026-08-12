#if os(iOS)

import Foundation
import XCTest
@testable import ExifTool

final class PhotoLibraryInfrastructureTests: XCTestCase {
    func testQueryCancellationReachesBackgroundEnumeration() async {
        let task = Task {
            await PhotoLibraryQueryService.run { cancellation in
                var iterations = 0
                while !cancellation.isCancelled, iterations < 10_000 {
                    Thread.sleep(forTimeInterval: 0.001)
                    iterations += 1
                }
                return (iterations, cancellation.isCancelled)
            }
        }

        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let (iterations, observedCancellation) = await task.value

        XCTAssertTrue(observedCancellation)
        XCTAssertLessThan(iterations, 10_000)
    }

    func testThumbnailSizesUseStablePixelBuckets() {
        XCTAssertEqual(ThumbnailSizeBucket.pixelLength(for: 180), 360)
        XCTAssertEqual(ThumbnailSizeBucket.pixelLength(for: 360), 360)
        XCTAssertEqual(ThumbnailSizeBucket.pixelLength(for: 361), 720)
        XCTAssertEqual(ThumbnailSizeBucket.pixelLength(for: 721), 1_080)
        XCTAssertEqual(ThumbnailSizeBucket.pixelLength(for: 3_000), 1_080)
    }
}

#endif
