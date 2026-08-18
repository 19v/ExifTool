#if os(iOS)

import XCTest
@testable import ExifTool

final class OrderedPhotoAssetsTests: XCTestCase {
    @MainActor
    func testPreservesAscendingOrderWhenOldestIsFirst() {
        let assets = [makeAsset(id: "oldest"), makeAsset(id: "middle"), makeAsset(id: "newest")]

        let ordered = OrderedPhotoAssets(assets: assets, sortOrder: .oldestFirst)

        XCTAssertEqual(ordered.map(\.id), ["oldest", "middle", "newest"])
    }

    @MainActor
    func testReversesTraversalWithoutChangingAssetIdentity() {
        let assets = [makeAsset(id: "oldest"), makeAsset(id: "middle"), makeAsset(id: "newest")]

        let ordered = OrderedPhotoAssets(assets: assets, sortOrder: .newestFirst)

        XCTAssertEqual(ordered.map(\.id), ["newest", "middle", "oldest"])
        XCTAssertEqual(ordered[0].id, assets[2].id)
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
