import XCTest
@testable import ExifTool

final class PhotoSearchMatcherTests: XCTestCase {
    func testMatchesCaseInsensitivelyAndPreservesSourceOrder() {
        let documents = [
            PhotoSearchDocument(assetID: "first", text: "IMG_0001.JPG 4032x3024"),
            PhotoSearchDocument(assetID: "second", text: "Summer Trip.heic 3024x4032"),
            PhotoSearchDocument(assetID: "third", text: "img_0002.jpg 6000x4000")
        ]

        XCTAssertEqual(
            PhotoSearchMatcher.matchingAssetIDs(query: "IMG_", documents: documents),
            ["first", "third"]
        )
    }

    func testMatchesDiacriticsUsingLocalizedComparison() {
        let documents = [
            PhotoSearchDocument(assetID: "cafe", text: "Café.jpg")
        ]

        XCTAssertEqual(
            PhotoSearchMatcher.matchingAssetIDs(query: "cafe", documents: documents),
            ["cafe"]
        )
    }

    func testWhitespaceOnlyQueryReturnsNoResults() {
        let documents = [PhotoSearchDocument(assetID: "photo", text: "photo.jpg")]

        XCTAssertTrue(
            PhotoSearchMatcher.matchingAssetIDs(query: "  \n ", documents: documents).isEmpty
        )
    }
}
