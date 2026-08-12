#if os(iOS)

import XCTest
@testable import ExifTool

final class PhotoSearchViewModelTests: XCTestCase {
    @MainActor
    func testSourceChangesIncrementallyAddAndRemoveSearchDocuments() async {
        let alpha = makeAsset(id: "alpha", fileName: "alpha.jpg")
        let beta = makeAsset(id: "beta", fileName: "beta.jpg")
        let gamma = makeAsset(id: "gamma", fileName: "gamma.jpg")
        let model = PhotoSearchViewModel()

        model.setSourceAssets([alpha, beta])
        model.query = "alpha"
        await waitUntil { model.results.map(\.id) == [alpha.id] }

        model.setSourceAssets([alpha, gamma])
        model.query = "gamma"
        await waitUntil { model.results.map(\.id) == [gamma.id] }

        model.query = "beta"
        await waitUntil { !model.isSearching }
        XCTAssertTrue(model.results.isEmpty)
    }

    @MainActor
    private func makeAsset(id: String, fileName: String) -> PhotoAsset {
        PhotoAsset(file: LocalPhotoFile(
            id: id,
            fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
            fileName: fileName,
            data: nil,
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1
        ))
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
}

#endif
