//
//  LibraryAuthorizationContent.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct LibraryAuthorizationContent<Content: View>: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let emptyTitle: String
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
            return "当前只显示已经下载到本地的照片。可以先去系统相册下载原图，或到设置里关闭这个筛选。"
        }

        return "当前权限范围内没有照片。"
    }
}
