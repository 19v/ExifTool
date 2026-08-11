//
//  SharedPhotoImport.swift
//  ExifTool
//
//  Created by Codex on 2026/4/17.
//

#if os(iOS)

import Foundation

enum SharedPhotoImport {
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

    private static func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty && !fileName.contains("/") && !fileName.contains("\\") && fileName != "." && fileName != ".."
    }
}

#endif
