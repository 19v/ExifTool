//
//  PhotoPickerTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoPickerTabView: View {
    @ObservedObject var library: PhotoLibraryViewModel
    #if os(iOS)
    @ObservedObject var manualPicker: ManualPhotoPickerViewModel
    #endif
    let readOnlyMode: Bool

    var body: some View {
        NavigationStack {
            Group {
                #if os(iOS)
                switch library.authorizationState {
                case .denied:
                    ManualPhotoPickerAccessView(picker: manualPicker, readOnlyMode: readOnlyMode)
                default:
                    LibraryAuthorizationContent(library: library, emptyTitle: "没有可显示的照片") {
                        PhotoAssetGridView(
                            assets: library.assets,
                            readOnlyMode: readOnlyMode,
                            isLoadingMore: library.showsOnlyLocalAssets && library.hasMoreLocalAssets,
                            onAssetAppear: library.loadMoreLocalAssetsIfNeeded,
                            onRefresh: library.refresh
                        )
                    }
                }
                #else
                LibraryAuthorizationContent(library: library, emptyTitle: "没有可显示的照片") {
                    PhotoAssetGridView(
                        assets: library.assets,
                        readOnlyMode: readOnlyMode,
                        isLoadingMore: false,
                        onRefresh: library.refresh
                    )
                }
                #endif
            }
            .navigationTitle("照片")
            .platformInlineNavigationTitle()
            .safeAreaInset(edge: .bottom) {
                if let snapshot = library.localPhotosPickerBannerSnapshot {
                    LocalPhotosStatusBanner(
                        snapshot: snapshot,
                        emphasis: .floating
                    )
                }
            }
        }
    }
}
