//
//  MacPhotoWorkspace.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Foundation
import Observation
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

#if os(macOS)
let macPhotoViewerWindowID = "mac-photo-viewer"

extension FocusedValues {
    @Entry var macPhotoWorkspace: MacPhotoWorkspace?
}

@MainActor
@Observable
final class MacPhotoWorkspace {
    private enum DefaultsKey {
        static let sortMode = "macPhotoSortMode"
        static let recentFilePaths = "macRecentFilePaths"
        static let recentFileBookmarks = "macRecentFileBookmarks"
    }

    enum SortMode: String, CaseIterable, Equatable, Identifiable {
        case fileName
        case creationDateNewest
        case creationDateOldest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fileName:
                return AppLocalization.string("mac.sort.fileName")
            case .creationDateNewest:
                return AppLocalization.string("mac.sort.creationDateNewest")
            case .creationDateOldest:
                return AppLocalization.string("mac.sort.creationDateOldest")
            }
        }
    }

    @ObservationIgnored private var importedAssets: [PhotoAsset] = []
    @ObservationIgnored private var activeSecurityScopedURLs: [String: URL] = [:]
    private(set) var sortedAssets: [PhotoAsset] = []
    var selectedAssetID: String?
    var sortMode: SortMode {
        didSet {
            UserDefaults.standard.set(sortMode.rawValue, forKey: DefaultsKey.sortMode)
            refreshSortedAssets()
        }
    }
    private(set) var recentFiles: [URL]

    init(initialFileURLs: [URL] = []) {
        sortMode = Self.persistedSortMode
        let restoredRecentFiles = Self.restoreRecentFiles()
        recentFiles = restoredRecentFiles.urls
        activeSecurityScopedURLs = restoredRecentFiles.activeURLs

        if !initialFileURLs.isEmpty {
            Task { [weak self] in
                _ = await self?.importFiles(from: initialFileURLs)
            }
        }
    }

    deinit {
        for url in activeSecurityScopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func refreshSortedAssets() {
        switch sortMode {
        case .fileName:
            sortedAssets = importedAssets.sorted {
                ($0.displayName ?? $0.id).localizedStandardCompare($1.displayName ?? $1.id) == .orderedAscending
            }
        case .creationDateNewest:
            sortedAssets = importedAssets.sorted { lhs, rhs in
                compareDates(lhs.creationDate, rhs.creationDate, newestFirst: true, lhs: lhs, rhs: rhs)
            }
        case .creationDateOldest:
            sortedAssets = importedAssets.sorted { lhs, rhs in
                compareDates(lhs.creationDate, rhs.creationDate, newestFirst: false, lhs: lhs, rhs: rhs)
            }
        }
    }

    var currentAsset: PhotoAsset? {
        guard let selectedAssetID else {
            return sortedAssets.first
        }

        return sortedAssets.first(where: { $0.id == selectedAssetID })
    }

    var currentFileURL: URL? {
        currentAsset?.localFile.fileURL
    }

    var windowTitle: String {
        currentAsset?.displayName ?? Self.appDisplayName
    }

    private static var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Exif Tool"
    }

    private static func restoreRecentFiles() -> (urls: [URL], activeURLs: [String: URL]) {
        let defaults = UserDefaults.standard
        let bookmarkData = defaults.array(forKey: DefaultsKey.recentFileBookmarks) as? [Data] ?? []
        var urls: [URL] = []
        var activeURLs: [String: URL] = [:]
        var refreshedBookmarks: [Data] = []

        for data in bookmarkData {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: url.path()) else {
                continue
            }

            let normalizedURL = url.standardizedFileURL
            let path = normalizedURL.path()
            if normalizedURL.startAccessingSecurityScopedResource() {
                activeURLs[path] = normalizedURL
            }
            urls.append(normalizedURL)

            if isStale,
               let refreshedData = try? normalizedURL.bookmarkData(
                   options: .withSecurityScope,
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                refreshedBookmarks.append(refreshedData)
            } else {
                refreshedBookmarks.append(data)
            }
        }

        if bookmarkData.isEmpty {
            let legacyURLs = (defaults.stringArray(forKey: DefaultsKey.recentFilePaths) ?? [])
                .map(URL.init(fileURLWithPath:))
                .filter { FileManager.default.fileExists(atPath: $0.path()) }
            urls = legacyURLs
            refreshedBookmarks = legacyURLs.compactMap(Self.bookmarkData(for:))
        }

        defaults.set(refreshedBookmarks, forKey: DefaultsKey.recentFileBookmarks)
        defaults.removeObject(forKey: DefaultsKey.recentFilePaths)
        return (Array(urls.prefix(8)), activeURLs)
    }

    func importFiles(from urls: [URL]) async -> Bool {
        let normalizedURLs = urls.map(\.standardizedFileURL)
        let newlyAccessedPaths = beginAccessingSecurityScopes(for: normalizedURLs)
        let importedAssets = await MediaProcessing.run {
            PhotoFileImporter.importAssets(from: normalizedURLs)
        }
        guard !importedAssets.isEmpty else {
            endAccessingSecurityScopes(for: newlyAccessedPaths)
            return false
        }

        self.importedAssets = importedAssets
        refreshSortedAssets()
        selectedAssetID = sortedAssets.first?.id
        let importedURLs = importedAssets.map(\.localFile.fileURL)
        let importedPaths = Set(importedURLs.map { $0.standardizedFileURL.path() })
        endAccessingSecurityScopes(for: newlyAccessedPaths.subtracting(importedPaths))
        updateRecentFiles(with: importedURLs)
        return true
    }

    func openRecentFile(_ url: URL) async -> Bool {
        await importFiles(from: [url])
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = Self.appDisplayName
        panel.message = AppLocalization.string("mac.openPanel.message")
        panel.prompt = AppLocalization.string("mac.openPanel.prompt")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else {
            return
        }

        Task { [weak self] in
            _ = await self?.importFiles(from: panel.urls)
        }
    }

    func revealCurrentFileInFinder() {
        guard let currentFileURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([currentFileURL])
    }

    func openCurrentFileInDefaultApp() {
        guard let currentFileURL else {
            return
        }

        NSWorkspace.shared.open(currentFileURL)
    }

    func copyCurrentFilePath() {
        guard let currentFileURL else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentFileURL.path(), forType: .string)
    }

    func clear() {
        importedAssets = []
        sortedAssets = []
        selectedAssetID = nil
        releaseUnusedSecurityScopes()
    }

    func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.recentFilePaths)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.recentFileBookmarks)
        recentFiles = []
        releaseUnusedSecurityScopes()
    }

    func selectNextAsset() {
        guard !sortedAssets.isEmpty else {
            return
        }

        guard let selectedAssetID,
              let currentIndex = sortedAssets.firstIndex(where: { $0.id == selectedAssetID }) else {
            self.selectedAssetID = sortedAssets.first?.id
            return
        }

        let nextIndex = min(currentIndex + 1, sortedAssets.count - 1)
        self.selectedAssetID = sortedAssets[nextIndex].id
    }

    func selectPreviousAsset() {
        guard !sortedAssets.isEmpty else {
            return
        }

        guard let selectedAssetID,
              let currentIndex = sortedAssets.firstIndex(where: { $0.id == selectedAssetID }) else {
            self.selectedAssetID = sortedAssets.first?.id
            return
        }

        let previousIndex = max(currentIndex - 1, 0)
        self.selectedAssetID = sortedAssets[previousIndex].id
    }

    var canSelectNextAsset: Bool {
        guard let selectedAssetID,
              let currentIndex = sortedAssets.firstIndex(where: { $0.id == selectedAssetID }) else {
            return sortedAssets.count > 1
        }

        return currentIndex < sortedAssets.count - 1
    }

    var canSelectPreviousAsset: Bool {
        guard let selectedAssetID,
              let currentIndex = sortedAssets.firstIndex(where: { $0.id == selectedAssetID }) else {
            return sortedAssets.count > 1
        }

        return currentIndex > 0
    }

    var hasCurrentFile: Bool {
        currentFileURL != nil
    }

    var currentFilePath: String? {
        currentFileURL?.path()
    }

    private static var persistedSortMode: SortMode {
        UserDefaults.standard.string(forKey: DefaultsKey.sortMode)
            .flatMap(SortMode.init(rawValue:))
            ?? .fileName
    }

    private func compareDates(
        _ lhsDate: Date?,
        _ rhsDate: Date?,
        newestFirst: Bool,
        lhs: PhotoAsset,
        rhs: PhotoAsset
    ) -> Bool {
        switch (lhsDate, rhsDate) {
        case let (left?, right?):
            return newestFirst ? left > right : left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return (lhs.displayName ?? lhs.id).localizedStandardCompare(rhs.displayName ?? rhs.id) == .orderedAscending
        }
    }

    private func updateRecentFiles(with urls: [URL]) {
        var mergedURLs = urls.map(\.standardizedFileURL)
        for url in recentFiles where !mergedURLs.contains(where: { $0.path() == url.path() }) {
            mergedURLs.append(url)
        }

        recentFiles = Array(mergedURLs.prefix(8))
        let bookmarks = recentFiles.compactMap(Self.bookmarkData(for:))
        UserDefaults.standard.set(bookmarks, forKey: DefaultsKey.recentFileBookmarks)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.recentFilePaths)
        releaseUnusedSecurityScopes()
    }

    private static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func beginAccessingSecurityScopes(for urls: [URL]) -> Set<String> {
        var newlyAccessedPaths = Set<String>()
        for url in urls {
            let path = url.path()
            guard activeSecurityScopedURLs[path] == nil,
                  url.startAccessingSecurityScopedResource() else {
                continue
            }
            activeSecurityScopedURLs[path] = url
            newlyAccessedPaths.insert(path)
        }
        return newlyAccessedPaths
    }

    private func endAccessingSecurityScopes(for paths: Set<String>) {
        for path in paths {
            activeSecurityScopedURLs.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
        }
    }

    private func releaseUnusedSecurityScopes() {
        let retainedPaths = Set(importedAssets.map { $0.localFile.fileURL.standardizedFileURL.path() })
            .union(recentFiles.map { $0.standardizedFileURL.path() })
        endAccessingSecurityScopes(for: Set(activeSecurityScopedURLs.keys).subtracting(retainedPaths))
    }
}
#endif
