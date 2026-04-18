//
//  ManualPhotoPickerViewModel.swift
//  ExifTool
//
//  Created by Codex on 2026/4/15.
//

#if os(iOS)

import Combine
internal import PhotosUI
import SwiftUI

@MainActor
final class ManualPhotoPickerViewModel: ObservableObject {
    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var isImporting = false
    @Published var importErrorMessage: String?

    @discardableResult
    func importPhotos(from items: [PhotosPickerItem]) async -> [PhotoAsset] {
        guard !items.isEmpty else {
            return []
        }

        isImporting = true
        defer { isImporting = false }

        var importedAssets: [PhotoAsset] = []
        importedAssets.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let suggestedFileName = item.supportedContentTypes.first?.preferredFilenameExtension.map {
                    "\(AppLocalization.string("photoFileImporter.pickedImage")) \(index + 1).\($0)"
                } ?? "\(AppLocalization.string("photoFileImporter.pickedImage")) \(index + 1)"

                if let asset = PhotoFileImporter.importAsset(
                    from: data,
                    suggestedFileName: suggestedFileName,
                    id: item.itemIdentifier ?? UUID().uuidString
                ) {
                    importedAssets.append(asset)
                }
            } catch {
                importErrorMessage = AppLocalization.string("manualPicker.partialFailure")
            }
        }

        if !importedAssets.isEmpty {
            assets = importedAssets
        } else if importErrorMessage == nil {
            importErrorMessage = AppLocalization.string("manualPicker.noReadableImages")
        }

        return importedAssets
    }

    func importSharedPhoto(from url: URL) -> PhotoAsset? {
        guard let asset = PhotoFileImporter.importAsset(from: url) else {
            importErrorMessage = AppLocalization.string("manualPicker.noSharedImage")
            return nil
        }

        assets = [asset]
        return asset
    }

    func clearAssets() {
        assets = []
    }

    func clearError() {
        importErrorMessage = nil
    }
}

#endif
