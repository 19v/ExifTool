#if os(iOS)

//
//  PhotoDetailView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoDetailView: View {
    let assets: [PhotoAsset]
    let sortOrder: PhotoAssetSortOrder

    @State private var currentAssetID: String
    @State private var showsChineseKeys: Bool

    init(
        assets: [PhotoAsset],
        initialAssetID: String,
        sortOrder: PhotoAssetSortOrder = .oldestFirst
    ) {
        self.assets = assets
        self.sortOrder = sortOrder
        _currentAssetID = State(initialValue: initialAssetID)
        _showsChineseKeys = State(initialValue: MetadataLanguagePreference.defaultShowsChineseKeys)
    }

    var body: some View {
        Group {
            if let currentAsset {
                PhotoDetailPage(
                    asset: currentAsset,
                    showsChineseKeys: $showsChineseKeys,
                    navigationTitle: navigationTitle,
                    photoNavigation: photoNavigation
                )
            } else {
                ContentUnavailableView("没有可显示的照片", systemImage: "photo")
            }
        }
        .onAppear {
            ensureCurrentAssetExists()
        }
        .onChange(of: assets.map(\.id)) {
            ensureCurrentAssetExists()
        }
    }

    private var navigationTitle: String {
        guard let currentIndex else {
            return AppLocalization.string("photoDetail.title")
        }

        return AppLocalization.string("photoDetail.title.indexed", currentIndex + 1, assets.count)
    }

    private var currentAsset: PhotoAsset? {
        assets.first(where: { $0.id == currentAssetID }) ?? assets.first
    }

    private var currentIndex: Int? {
        guard let currentAsset else {
            return nil
        }

        return orderedAssets.firstIndex(where: { $0.id == currentAsset.id })
    }

    private var photoNavigation: PhotoNavigationConfiguration? {
        guard assets.count > 1, let currentIndex else {
            return nil
        }

        return PhotoNavigationConfiguration(
            canSelectPrevious: currentIndex > 0,
            canSelectNext: currentIndex < assets.count - 1,
            selectPrevious: selectPreviousAsset,
            selectNext: selectNextAsset
        )
    }

    private func selectPreviousAsset() {
        guard let currentIndex, currentIndex > 0 else {
            return
        }

        currentAssetID = orderedAssets[currentIndex - 1].id
    }

    private func selectNextAsset() {
        guard let currentIndex, currentIndex < assets.count - 1 else {
            return
        }

        currentAssetID = orderedAssets[currentIndex + 1].id
    }

    private func ensureCurrentAssetExists() {
        guard currentAsset == nil, let firstAsset = orderedAssets.first else {
            return
        }

        currentAssetID = firstAsset.id
    }

    private var orderedAssets: OrderedPhotoAssets {
        OrderedPhotoAssets(assets: assets, sortOrder: sortOrder)
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

#endif

