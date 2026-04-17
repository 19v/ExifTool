//
//  AlbumsTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct AlbumsTabView: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let readOnlyMode: Bool

    var body: some View {
        NavigationStack {
            LibraryAuthorizationContent(library: library, emptyTitle: "没有找到相册") {
                PlatformAlbumList(
                    albums: library.albums,
                    readOnlyMode: readOnlyMode,
                    showsOnlyLocalAssets: library.showsOnlyLocalAssets,
                    onRefresh: library.refresh
                )
            }
            .navigationTitle("相册")
            .platformInlineNavigationTitle()
            .task(id: library.showsOnlyLocalAssets) {
                if library.showsOnlyLocalAssets {
                    library.buildRemainingLocalAlbumStatsIfNeeded()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let snapshot = library.localPhotosAlbumBannerSnapshot {
                    LocalPhotosStatusBanner(snapshot: snapshot, emphasis: .floating)
                }
            }
        }
    }
}

struct AlbumRowView: View {
    let album: PhotoAlbum

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.body)
                Text("\(album.assetCount) 张照片")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AlbumDetailView: View {
    let album: PhotoAlbum
    let readOnlyMode: Bool
    let showsOnlyLocalAssets: Bool

    @StateObject private var pager = LocalAssetPagingViewModel()
    @State private var allAssets: [PhotoAsset] = []

    var body: some View {
        PhotoAssetGridView(
            assets: displayedAssets,
            readOnlyMode: readOnlyMode,
            isLoadingMore: showsOnlyLocalAssets ? pager.hasMoreAssets : false,
            onAssetAppear: assetAppearHandler
        )
        .navigationTitle(album.title)
        .platformInlineNavigationTitle()
        .task(id: album.id) {
            let fetchedAssets = await PhotoLibraryViewModel.fetchImageAssetsOffMain(in: album.collection)
            allAssets = fetchedAssets
            if showsOnlyLocalAssets {
                pager.setSourceAssets(fetchedAssets)
            } else {
                pager.reset()
            }
        }
    }

    private var displayedAssets: [PhotoAsset] {
        showsOnlyLocalAssets ? pager.assets : allAssets
    }

    private var assetAppearHandler: ((String?) -> Void)? {
        showsOnlyLocalAssets ? { pager.loadMoreIfNeeded(currentAssetID: $0) } : nil
    }
}
