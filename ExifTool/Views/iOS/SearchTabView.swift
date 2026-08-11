#if os(iOS)

//
//  SearchTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct SearchTabView: View {
    let library: PhotoLibraryViewModel
    let readOnlyMode: Bool

    @State private var searchModel = PhotoSearchViewModel()
    @State private var pager = LocalAssetPagingViewModel()

    var body: some View {
        @Bindable var searchModel = searchModel

        NavigationStack {
            LibraryAuthorizationContent(library: library, emptyTitle: "没有可搜索的照片") {
                SearchResultsContent(
                    hasQuery: searchModel.hasQuery,
                    assets: displayedSearchAssets,
                    readOnlyMode: readOnlyMode,
                    isSearching: searchModel.isSearching,
                    isLoadingMore: showsLocalSearchLoading,
                    onAssetAppear: searchAssetAppearHandler,
                    onRefresh: library.refresh
                )
            }
            .navigationTitle("搜索")
            .searchable(text: $searchModel.query, prompt: "搜索照片")
            .task(id: library.searchableAssetsRevision) {
                searchModel.setSourceAssets(library.searchableAssets)
            }
            .task(id: searchModel.resultsRevision) {
                refreshSearchPager()
            }
            .task(id: library.showsOnlyLocalAssets) {
                refreshSearchPager()
            }
            .safeAreaInset(edge: .bottom) {
                if let snapshot = searchBannerSnapshot {
                    LocalPhotosStatusBanner(
                        snapshot: snapshot,
                        emphasis: .floating
                    )
                }
            }
        }
    }

    private var displayedSearchAssets: [PhotoAsset] {
        library.showsOnlyLocalAssets ? pager.assets : searchModel.results
    }

    private var showsLocalSearchLoading: Bool {
        library.showsOnlyLocalAssets && pager.hasMoreAssets
    }

    private var searchAssetAppearHandler: ((String?) -> Void)? {
        library.showsOnlyLocalAssets ? { pager.loadMoreIfNeeded(currentAssetID: $0) } : nil
    }

    private func refreshSearchPager() {
        if library.showsOnlyLocalAssets {
            pager.setSourceAssets(searchModel.results)
        } else {
            pager.reset()
        }
    }

    private var searchBannerSnapshot: LocalPhotosStatusSnapshot? {
        guard searchModel.hasQuery else {
            return nil
        }

        if displayedSearchAssets.isEmpty && (searchModel.isSearching || showsLocalSearchLoading) {
            return LocalPhotosStatusSnapshot(
                text: AppLocalization.string("search.localPhotos.loading"),
                state: .loading,
                localPhotosCount: displayedSearchAssets.count,
                localAlbumsCount: nil
            )
        }

        if showsLocalSearchLoading {
            return LocalPhotosStatusSnapshot(
                text: AppLocalization.string("search.localPhotos.more"),
                state: .paginating,
                localPhotosCount: displayedSearchAssets.count,
                localAlbumsCount: nil
            )
        }

        if library.isBuildingLocalAlbumStats {
            return LocalPhotosStatusSnapshot(
                text: AppLocalization.string("search.localPhotos.buildingAlbums"),
                state: .buildingAlbums,
                localPhotosCount: displayedSearchAssets.count,
                localAlbumsCount: library.localAlbumsCount
            )
        }

        return nil
    }
}

private struct SearchResultsContent: View {
    let hasQuery: Bool
    let assets: [PhotoAsset]
    let readOnlyMode: Bool
    let isSearching: Bool
    let isLoadingMore: Bool
    let onAssetAppear: ((String?) -> Void)?
    let onRefresh: (() async -> Void)?

    var body: some View {
        if !hasQuery {
            ContentUnavailableView(
                "搜索照片",
                systemImage: "magnifyingglass",
                description: Text("可以搜索日期、尺寸或照片标识符。")
            )
        } else if assets.isEmpty && isSearching {
            ProgressView("正在搜索")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if assets.isEmpty && !isLoadingMore {
            ContentUnavailableView("没有匹配照片", systemImage: "photo.on.rectangle.angled")
        } else {
            PhotoAssetGridView(
                assets: assets,
                readOnlyMode: readOnlyMode,
                showsReadOnlyOverlay: false,
                isLoadingMore: isLoadingMore,
                onAssetAppear: onAssetAppear,
                onRefresh: onRefresh
            )
        }
    }
}

#endif
