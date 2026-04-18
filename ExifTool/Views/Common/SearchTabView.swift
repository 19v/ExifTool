//
//  SearchTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct SearchTabView: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let readOnlyMode: Bool

    @State private var query = ""
    @StateObject private var pager = LocalAssetPagingViewModel()

    private var results: [PhotoAsset] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        return library.searchableAssets.filter { asset in
            PhotoSearchIndex.text(for: asset).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            LibraryAuthorizationContent(library: library, emptyTitle: "没有可搜索的照片") {
                searchContent
            }
            .navigationTitle("搜索")
            .platformInlineNavigationTitle()
            .searchable(text: $query, prompt: "搜索照片")
            .onChange(of: query) { _, _ in
                refreshSearchPager()
            }
            .onChange(of: library.showsOnlyLocalAssets) { _, _ in
                refreshSearchPager()
            }
            .onChange(of: library.searchableAssets.map(\.id)) { _, _ in
                refreshSearchPager()
            }
            .task {
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
        library.showsOnlyLocalAssets ? pager.assets : results
    }

    private var showsSearchLoading: Bool {
        library.showsOnlyLocalAssets && pager.hasMoreAssets
    }

    @ViewBuilder
    private var searchContent: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("搜索照片", systemImage: "magnifyingglass", description: Text("可以搜索日期、尺寸或照片标识符。"))
        } else if displayedSearchAssets.isEmpty && !showsSearchLoading {
            ContentUnavailableView("没有匹配照片", systemImage: "photo.on.rectangle.angled")
        } else {
            PhotoAssetGridView(
                assets: displayedSearchAssets,
                readOnlyMode: readOnlyMode,
                isLoadingMore: showsSearchLoading,
                onAssetAppear: searchAssetAppearHandler,
                onRefresh: library.refresh
            )
        }
    }

    private var searchAssetAppearHandler: ((String?) -> Void)? {
        library.showsOnlyLocalAssets ? { pager.loadMoreIfNeeded(currentAssetID: $0) } : nil
    }

    private func refreshSearchPager() {
        if library.showsOnlyLocalAssets {
            pager.setSourceAssets(results)
        } else {
            pager.reset()
        }
    }

    private var searchBannerSnapshot: LocalPhotosStatusSnapshot? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if displayedSearchAssets.isEmpty && showsSearchLoading {
            return LocalPhotosStatusSnapshot(
                text: AppLocalization.string("search.localPhotos.loading"),
                state: .loading,
                localPhotosCount: displayedSearchAssets.count,
                localAlbumsCount: nil
            )
        }

        if showsSearchLoading {
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
