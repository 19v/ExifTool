//
//  SharedPhotoImport.swift
//  ExifTool
//
//  Created by Codex on 2026/4/17.
//

#if os(iOS)

import Foundation

nonisolated enum SharedPhotoImport {
    static let appGroupIdentifier = "group.com.echopie.ExifTool"
    static let urlScheme = "exiftool"
    static let urlHost = "shared-photo"
    static let sharedDirectoryName = "SharedPhotos"
    static let fileQueryItemName = "file"

    static func fileName(from url: URL) -> String? {
        guard url.scheme == urlScheme, url.host == urlHost else {
            return nil
        }

        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == fileQueryItemName })?
            .value
    }

    static func fileURL(forSharedFileName fileName: String) -> URL? {
        guard isSafeFileName(fileName),
              let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }

        return containerURL
            .appending(path: sharedDirectoryName, directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func removeSharedFile(at fileURL: URL) {
        guard isSharedFileURL(fileURL) else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func cleanupStaleFiles(olderThan maximumAge: TimeInterval = 24 * 60 * 60) {
        guard let directoryURL = sharedDirectoryURL(),
              let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-maximumAge)
        for fileURL in fileURLs {
            let modificationDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modificationDate.map({ $0 < cutoffDate }) ?? true {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private static func isSharedFileURL(_ fileURL: URL) -> Bool {
        guard let directoryURL = sharedDirectoryURL() else {
            return false
        }
        return fileURL.standardizedFileURL.deletingLastPathComponent() == directoryURL.standardizedFileURL
    }

    private static func sharedDirectoryURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appending(path: sharedDirectoryName, directoryHint: .isDirectory)
    }

    private static func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty && !fileName.contains("/") && !fileName.contains("\\") && fileName != "." && fileName != ".."
    }
}

#endif
