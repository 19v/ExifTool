//
//  PhotoDetailView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoDetailView: View {
    let assets: [PhotoAsset]
    let initialAssetID: String
    let readOnlyMode: Bool

    @State private var showsChineseKeys: Bool

    init(assets: [PhotoAsset], initialAssetID: String, readOnlyMode: Bool) {
        self.assets = assets
        self.initialAssetID = initialAssetID
        self.readOnlyMode = readOnlyMode
        _showsChineseKeys = State(initialValue: MetadataLanguagePreference.defaultShowsChineseKeys)
    }

    var body: some View {
        Group {
            if let currentAsset {
                PhotoDetailPage(
                    asset: currentAsset,
                    readOnlyMode: readOnlyMode,
                    showsChineseKeys: $showsChineseKeys,
                    navigationTitle: navigationTitle
                )
            } else {
                ContentUnavailableView("没有可显示的照片", systemImage: "photo")
            }
        }
    }

    private var navigationTitle: String {
        guard let currentIndex else {
            return AppLocalization.string("photoDetail.title")
        }

        return AppLocalization.string("photoDetail.title.indexed", currentIndex + 1, assets.count)
    }

    private var currentAsset: PhotoAsset? {
        assets.first(where: { $0.id == initialAssetID }) ?? assets.first
    }

    private var currentIndex: Int? {
        guard let currentAsset else {
            return nil
        }

        return assets.firstIndex(where: { $0.id == currentAsset.id })
    }
}

enum MetadataLanguagePreference {
    static var defaultShowsChineseKeys: Bool {
        guard let preferredLanguage = Locale.preferredLanguages.first else {
            return false
        }

        return Locale(identifier: preferredLanguage).language.languageCode?.identifier == "zh"
    }
}
