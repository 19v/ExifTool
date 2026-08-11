#if os(iOS)

//
//  LibraryAuthorizationContent.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct LibraryAuthorizationContent<Content: View>: View {
    let library: PhotoLibraryViewModel
    let emptyTitle: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if library.isFilteringLocalAssets && library.assets.isEmpty {
                ProgressView("正在筛选已下载到本地的照片")
            } else {
                switch library.authorizationState {
                case .unknown:
                    ProgressView("正在读取照片")
                case .denied:
                    ContentUnavailableView(
                        "无法访问照片",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("请在系统设置中允许读取照片。应用只读取照片，不会修改照片。")
                    )
                case .limited, .authorized:
                    content
                case .empty:
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "photo",
                        description: Text(emptyStateDescription)
                    )
                }
            }
        }
    }

    private var emptyStateDescription: String {
        if library.showsOnlyLocalAssets {
            return AppLocalization.string("library.empty.localOnly")
        }

        return AppLocalization.string("library.empty.noPhotos")
    }
}

#endif
