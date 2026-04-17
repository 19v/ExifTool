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

    @State private var showsChineseKeys = false

    init(assets: [PhotoAsset], initialAssetID: String, readOnlyMode: Bool) {
        self.assets = assets
        self.initialAssetID = initialAssetID
        self.readOnlyMode = readOnlyMode
    }

    var body: some View {
        Group {
            if let currentAsset {
                PhotoDetailPage(
                    asset: currentAsset,
                    readOnlyMode: readOnlyMode,
                    showsChineseKeys: showsChineseKeys
                )
            } else {
                ContentUnavailableView("没有可显示的照片", systemImage: "photo")
            }
        }
        .navigationTitle(navigationTitle)
        .platformInlineNavigationTitle()
        .platformTabBarHidden()
        .toolbar {
            ToolbarItem(placement: .platformLanguageToggle) {
                Button(showsChineseKeys ? "EN" : "中文") {
                    showsChineseKeys.toggle()
                }
                .accessibilityLabel(showsChineseKeys ? "切换为英文字段名" : "切换为中文字段名")
            }
        }
    }

    private var navigationTitle: String {
        guard let currentIndex else {
            return "照片信息"
        }

        return "照片信息 \(currentIndex + 1)/\(assets.count)"
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
