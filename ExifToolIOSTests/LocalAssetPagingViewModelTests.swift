#if os(iOS)

import XCTest
@testable import ExifTool

final class LocalAssetPagingViewModelTests: XCTestCase {
    @MainActor
    func testReplacingSourceWhilePreviousScanIsRunningLoadsNewestSession() async {
        let firstScanStarted = expectation(description: "First scan started")
        let firstAsset = makeAsset(id: "first")
        let secondAsset = makeAsset(id: "second")
        var didStartFirstScan = false

        let model = LocalAssetPagingViewModel { assets in
            if assets.first?.id == firstAsset.id {
                didStartFirstScan = true
                firstScanStarted.fulfill()
                try? await Task.sleep(for: .seconds(5))
            }
            return Set(assets.map(\.id))
        }

        model.setSourceAssets([firstAsset])
        await fulfillment(of: [firstScanStarted], timeout: 1)
        XCTAssertTrue(didStartFirstScan)

        model.setSourceAssets([secondAsset])
        await waitUntil(timeout: .seconds(1)) {
            model.assets.map(\.id) == [secondAsset.id]
        }

        XCTAssertEqual(model.assets.map(\.id), [secondAsset.id])
        XCTAssertFalse(model.hasMoreAssets)
    }

    @MainActor
    func testResetPreventsRunningScanFromPublishingResults() async {
        let scanStarted = expectation(description: "Scan started")
        let asset = makeAsset(id: "reset")
        let model = LocalAssetPagingViewModel { assets in
            scanStarted.fulfill()
            try? await Task.sleep(for: .seconds(5))
            return Set(assets.map(\.id))
        }

        model.setSourceAssets([asset])
        await fulfillment(of: [scanStarted], timeout: 1)
        model.reset()
        await Task.yield()

        XCTAssertTrue(model.assets.isEmpty)
        XCTAssertFalse(model.hasMoreAssets)
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

    @MainActor
    private func waitUntil(
        timeout: Duration,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

#endif
