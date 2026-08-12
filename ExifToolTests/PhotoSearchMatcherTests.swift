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

    func testMatchesWidthInsensitiveTextFromPrecomputedDocument() {
        let document = PhotoSearchDocument(assetID: "wide", text: "ＩＭＧ＿０００１．ＪＰＧ")

        XCTAssertEqual(
            PhotoSearchMatcher.matchingAssetIDs(query: "img_0001.jpg", documents: [document]),
            ["wide"]
        )
        XCTAssertEqual(document.normalizedText, "img_0001.jpg")
    }

    func testNormalizedQueryEntryPointMatchesPublicEntryPoint() {
        let documents = [
            PhotoSearchDocument(assetID: "first", text: "Café 4032x3024"),
            PhotoSearchDocument(assetID: "second", text: "Landscape 6000x4000")
        ]
        let normalizedQuery = PhotoSearchMatcher.normalized(" CAFÉ ")

        XCTAssertEqual(
            PhotoSearchMatcher.matchingAssetIDs(normalizedQuery: normalizedQuery, documents: documents),
            PhotoSearchMatcher.matchingAssetIDs(query: " CAFÉ ", documents: documents)
        )
    }

    func testWhitespaceOnlyQueryReturnsNoResults() {
        let documents = [PhotoSearchDocument(assetID: "photo", text: "photo.jpg")]

        XCTAssertTrue(
            PhotoSearchMatcher.matchingAssetIDs(query: "  \n ", documents: documents).isEmpty
        )
    }

    func testLargeSearchIndexPerformance() {
        let documents = (0..<100_000).map {
            PhotoSearchDocument(assetID: "asset-\($0)", text: "IMG_\($0).HEIC 4032x3024")
        }

        measure {
            XCTAssertEqual(
                PhotoSearchMatcher.matchingAssetIDs(query: "IMG_99999", documents: documents),
                ["asset-99999"]
            )
        }
    }
}
