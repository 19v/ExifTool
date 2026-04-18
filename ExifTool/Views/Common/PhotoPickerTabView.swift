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
    let onPhotoViewed: (() -> Void)?
    let onPhotoDetailVisibilityChanged: ((Bool) -> Void)?
    let onPresentLimitedLibraryPicker: (() -> Void)?
    @State private var isShowingPhotoDetail = false

    #if os(iOS)
    init(
        library: PhotoLibraryViewModel,
        manualPicker: ManualPhotoPickerViewModel,
        readOnlyMode: Bool,
        onPhotoViewed: (() -> Void)? = nil,
        onPhotoDetailVisibilityChanged: ((Bool) -> Void)? = nil,
        onPresentLimitedLibraryPicker: (() -> Void)? = nil
    ) {
        self.library = library
        self.manualPicker = manualPicker
        self.readOnlyMode = readOnlyMode
        self.onPhotoViewed = onPhotoViewed
        self.onPhotoDetailVisibilityChanged = onPhotoDetailVisibilityChanged
        self.onPresentLimitedLibraryPicker = onPresentLimitedLibraryPicker
    }
    #else
    init(
        library: PhotoLibraryViewModel,
        readOnlyMode: Bool,
        onPhotoViewed: (() -> Void)? = nil,
        onPhotoDetailVisibilityChanged: ((Bool) -> Void)? = nil
    ) {
        self.library = library
        self.readOnlyMode = readOnlyMode
        self.onPhotoViewed = onPhotoViewed
        self.onPhotoDetailVisibilityChanged = onPhotoDetailVisibilityChanged
        self.onPresentLimitedLibraryPicker = nil
    }
    #endif

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
                            showsReadOnlyOverlay: false,
                            isLoadingMore: library.showsOnlyLocalAssets && library.hasMoreLocalAssets,
                            onAssetAppear: library.loadMoreLocalAssetsIfNeeded,
                            onAssetOpen: handlePhotoDetailOpened,
                            onAssetClose: handlePhotoDetailClosed,
                            onRefresh: library.refresh
                        )
                    }
                }
                #else
                LibraryAuthorizationContent(library: library, emptyTitle: "没有可显示的照片") {
                    PhotoAssetGridView(
                        assets: library.assets,
                        readOnlyMode: readOnlyMode,
                        showsReadOnlyOverlay: false,
                        isLoadingMore: false,
                        onAssetOpen: handlePhotoDetailOpened,
                        onAssetClose: handlePhotoDetailClosed,
                        onRefresh: library.refresh
                    )
                }
                #endif
            }
            .navigationTitle("照片")
            #if os(iOS)
            .toolbar {
                if library.accessScope == .limited && !isShowingPhotoDetail {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(action: handleLimitedLibrarySelection) {
                                Label("重新选择照片", systemImage: "plus")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("更多操作")
                    }
                }
            }
            #endif
            .safeAreaInset(edge: .bottom) {
                if !isShowingPhotoDetail, let snapshot = library.localPhotosPickerBannerSnapshot {
                    LocalPhotosStatusBanner(
                        snapshot: snapshot,
                        emphasis: .floating
                    )
                }
            }
        }
    }

    private func handlePhotoDetailOpened() {
        isShowingPhotoDetail = true
        onPhotoDetailVisibilityChanged?(true)
        onPhotoViewed?()
    }

    private func handlePhotoDetailClosed() {
        isShowingPhotoDetail = false
        onPhotoDetailVisibilityChanged?(false)
    }

    private func handleLimitedLibrarySelection() {
        onPresentLimitedLibraryPicker?()
    }
}
