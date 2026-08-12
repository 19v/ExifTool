#if os(iOS)

import XCTest
@testable import ExifTool

final class ImportLifecycleIntegrationTests: XCTestCase {
    func testSharedPhotoURLAcceptsExpectedRouteAndRejectsTraversal() throws {
        let validURL = try XCTUnwrap(URL(string: "exiftool://shared-photo?file=photo.heic"))
        let wrongHost = try XCTUnwrap(URL(string: "exiftool://other?file=photo.heic"))
        let traversal = try XCTUnwrap(URL(string: "exiftool://shared-photo?file=../secret.jpg"))

        XCTAssertEqual(SharedPhotoImport.fileName(from: validURL), "photo.heic")
        XCTAssertNil(SharedPhotoImport.fileName(from: wrongHost))
        XCTAssertNil(SharedPhotoImport.fileURL(forSharedFileName: SharedPhotoImport.fileName(from: traversal) ?? ""))
    }

    func testManagedTemporaryFileIsRemovedButExternalFileIsPreserved() throws {
        let managedDirectory = FileManager.default.temporaryDirectory
            .appending(path: PhotoTemporaryFileStore.importsDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let managedURL = managedDirectory.appending(path: UUID().uuidString)
        try Data([1]).write(to: managedURL)

        let externalURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data([1]).write(to: externalURL)
        defer { try? FileManager.default.removeItem(at: externalURL) }

        PhotoTemporaryFileStore.removeIfManaged(managedURL)
        PhotoTemporaryFileStore.removeIfManaged(externalURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalURL.path))
    }
}

#endif
