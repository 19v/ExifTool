#if os(iOS)

import XCTest
@testable import ExifTool

final class LocalAssetAvailabilityIndexTests: XCTestCase {
    @MainActor
    func testConcurrentRequestsShareResolutionAndCacheResult() async {
        var resolutionCount = 0
        let asset = makeAsset(id: "shared")
        let index = LocalAssetAvailabilityIndex { assets in
            resolutionCount += 1
            try? await Task.sleep(for: .milliseconds(50))
            return Set(assets.map(\.id))
        }

        async let first = index.locallyAvailableIDs(in: [asset])
        async let second = index.locallyAvailableIDs(in: [asset])
        let values = await (first, second)

        XCTAssertEqual(values.0, [asset.id])
        XCTAssertEqual(values.1, [asset.id])
        XCTAssertEqual(resolutionCount, 1)

        let cached = await index.locallyAvailableIDs(in: [asset])
        XCTAssertEqual(cached, [asset.id])
        XCTAssertEqual(resolutionCount, 1)
    }

    @MainActor
    func testInvalidatingAssetForcesNewResolution() async {
        var resolutionCount = 0
        let asset = makeAsset(id: "invalidated")
        let index = LocalAssetAvailabilityIndex { assets in
            resolutionCount += 1
            return Set(assets.map(\.id))
        }

        _ = await index.locallyAvailableIDs(in: [asset])
        index.invalidate(assetIDs: [asset.id])
        _ = await index.locallyAvailableIDs(in: [asset])

        XCTAssertEqual(resolutionCount, 2)
    }

    @MainActor
    func testInvalidationPreventsCancelledResolutionFromPopulatingCache() async {
        let firstResolutionStarted = expectation(description: "First resolution started")
        var resolutionCount = 0
        let asset = makeAsset(id: "cancelled")
        let index = LocalAssetAvailabilityIndex { assets in
            resolutionCount += 1
            if resolutionCount == 1 {
                firstResolutionStarted.fulfill()
                try? await Task.sleep(for: .seconds(5))
                return []
            }
            return Set(assets.map(\.id))
        }

        let firstTask = Task { await index.locallyAvailableIDs(in: [asset]) }
        await fulfillment(of: [firstResolutionStarted], timeout: 1)
        index.invalidate(assetIDs: [asset.id])
        _ = await firstTask.value

        let refreshed = await index.locallyAvailableIDs(in: [asset])
        XCTAssertEqual(refreshed, [asset.id])
        XCTAssertEqual(resolutionCount, 2)
    }

    @MainActor
    private func makeAsset(id: String) -> PhotoAsset {
        PhotoAsset(file: LocalPhotoFile(
            id: id,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            fileName: "\(id).jpg",
            data: nil,
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1
        ))
    }
}

#endif
