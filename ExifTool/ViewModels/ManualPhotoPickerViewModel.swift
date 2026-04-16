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

    func importPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            return
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
                    "已选图片 \(index + 1).\($0)"
                } ?? "已选图片 \(index + 1)"

                if let asset = PhotoFileImporter.importAsset(
                    from: data,
                    suggestedFileName: suggestedFileName,
                    id: item.itemIdentifier ?? UUID().uuidString
                ) {
                    importedAssets.append(asset)
                }
            } catch {
                importErrorMessage = "有部分图片读取失败，请重试。"
            }
        }

        if !importedAssets.isEmpty {
            assets = importedAssets
        } else if importErrorMessage == nil {
            importErrorMessage = "没有成功导入可读取的图片。"
        }
    }

    func clearError() {
        importErrorMessage = nil
    }
}

#endif
