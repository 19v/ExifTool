//
//  MacPhotoWorkspace.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Combine
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

#if os(macOS)
let macPhotoViewerWindowID = "mac-photo-viewer"

private struct MacPhotoWorkspaceFocusedKey: FocusedValueKey {
    typealias Value = MacPhotoWorkspace
}

extension FocusedValues {
    var macPhotoWorkspace: MacPhotoWorkspace? {
        get { self[MacPhotoWorkspaceFocusedKey.self] }
        set { self[MacPhotoWorkspaceFocusedKey.self] = newValue }
    }
}

@MainActor
final class MacPhotoWorkspace: ObservableObject {
    private enum DefaultsKey {
        static let sortMode = "macPhotoSortMode"
        static let recentFilePaths = "macRecentFilePaths"
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case fileName
        case creationDateNewest
        case creationDateOldest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fileName:
                return "按文件名"
            case .creationDateNewest:
                return "按拍摄时间(新到旧)"
            case .creationDateOldest:
                return "按拍摄时间(旧到新)"
            }
        }
    }

    @Published private(set) var importedAssets: [PhotoAsset] = []
    @Published var selectedAssetID: String?
    @Published var sortMode: SortMode {
        didSet {
            UserDefaults.standard.set(sortMode.rawValue, forKey: DefaultsKey.sortMode)
        }
    }

    init(initialFileURLs: [URL] = []) {
        sortMode = Self.persistedSortMode

        if !initialFileURLs.isEmpty {
            _ = importFiles(from: initialFileURLs)
        }
    }

    var sortedAssets: [PhotoAsset] {
        switch sortMode {
        case .fileName:
            return importedAssets.sorted {
                ($0.displayName ?? $0.id).localizedStandardCompare($1.displayName ?? $1.id) == .orderedAscending
            }
        case .creationDateNewest:
            return importedAssets.sorted { lhs, rhs in
                compareDates(lhs.creationDate, rhs.creationDate, newestFirst: true, lhs: lhs, rhs: rhs)
            }
        case .creationDateOldest:
            return importedAssets.sorted { lhs, rhs in
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
        currentAsset?.localFile?.fileURL
    }

    var windowTitle: String {
        currentAsset?.displayName ?? "照片"
    }

    var recentFiles: [URL] {
        let storedPaths = UserDefaults.standard.stringArray(forKey: DefaultsKey.recentFilePaths) ?? []
        return storedPaths
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path()) }
    }

    func importFiles(from urls: [URL]) -> Bool {
        let importedAssets = PhotoFileImporter.importAssets(from: urls)
        guard !importedAssets.isEmpty else {
            return false
        }

        self.importedAssets = importedAssets
        selectedAssetID = sortedAssets.first?.id
        updateRecentFiles(with: urls)
        return true
    }

    func openRecentFile(_ url: URL) -> Bool {
        importFiles(from: [url])
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择照片"
        panel.message = "选择一张或多张图片来查看 Exif。"
        panel.prompt = "打开"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK else {
            return
        }

        _ = importFiles(from: panel.urls)
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
        selectedAssetID = nil
    }

    func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.recentFilePaths)
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
        let normalizedNewPaths = urls.map { $0.standardizedFileURL.path() }
        let existingPaths = UserDefaults.standard.stringArray(forKey: DefaultsKey.recentFilePaths) ?? []

        var mergedPaths: [String] = normalizedNewPaths
        for path in existingPaths where !mergedPaths.contains(path) {
            mergedPaths.append(path)
        }

        UserDefaults.standard.set(Array(mergedPaths.prefix(8)), forKey: DefaultsKey.recentFilePaths)
    }
}
#endif
