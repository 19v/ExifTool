//
//  PhotoPickerTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoPickerTabView: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let readOnlyMode: Bool
    let onPresentLimitedLibraryPicker: (() -> Void)?

    #if os(iOS)
    init(
        library: PhotoLibraryViewModel,
        readOnlyMode: Bool,
        onPresentLimitedLibraryPicker: (() -> Void)? = nil
    ) {
        self.library = library
        self.readOnlyMode = readOnlyMode
        self.onPresentLimitedLibraryPicker = onPresentLimitedLibraryPicker
    }
    #else
    init(
        library: PhotoLibraryViewModel,
        readOnlyMode: Bool
    ) {
        self.library = library
        self.readOnlyMode = readOnlyMode
        self.onPresentLimitedLibraryPicker = nil
    }
    #endif

    var body: some View {
        NavigationStack {
            Group {
                LibraryAuthorizationContent(library: library, emptyTitle: "没有可显示的照片") {
                    PhotoAssetGridView(
                        assets: library.assets,
                        readOnlyMode: readOnlyMode,
                        showsReadOnlyOverlay: false,
                        isLoadingMore: library.showsOnlyLocalAssets && library.hasMoreLocalAssets,
                        onAssetAppear: library.loadMoreLocalAssetsIfNeeded,
                        onRefresh: library.refresh
                    )
                }
            }
            .navigationTitle("照片")
            #if os(iOS)
            .toolbar {
                if library.accessScope == .limited {
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
                if let snapshot = library.localPhotosPickerBannerSnapshot {
                    LocalPhotosStatusBanner(
                        snapshot: snapshot,
                        emphasis: .floating
                    )
                }
            }
        }
    }

    private func handleLimitedLibrarySelection() {
        onPresentLimitedLibraryPicker?()
    }
}
