//
//  PlatformAlbumList+iOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

import SwiftUI

struct PlatformAlbumList: View {
    let albums: [PhotoAlbum]
    let readOnlyMode: Bool
    let showsOnlyLocalAssets: Bool
    let albumContentRevisions: CollectionRevisionIndex
    let onRefresh: (() async -> Void)?

    init(
        albums: [PhotoAlbum],
        readOnlyMode: Bool,
        showsOnlyLocalAssets: Bool = false,
        albumContentRevisions: CollectionRevisionIndex = CollectionRevisionIndex(),
        onRefresh: (() async -> Void)? = nil
    ) {
        self.albums = albums
        self.readOnlyMode = readOnlyMode
        self.showsOnlyLocalAssets = showsOnlyLocalAssets
        self.albumContentRevisions = albumContentRevisions
        self.onRefresh = onRefresh
    }

    var body: some View {
        List(albums) { album in
            NavigationLink {
                AlbumDetailView(
                    album: album,
                    readOnlyMode: readOnlyMode,
                    showsOnlyLocalAssets: showsOnlyLocalAssets,
                    albumContentRevision: albumContentRevisions[album.id]
                )
            } label: {
                AlbumRowView(album: album)
            }
        }
        .refreshable {
            await onRefresh?()
        }
        .listStyle(.insetGrouped)
    }
}

#endif
