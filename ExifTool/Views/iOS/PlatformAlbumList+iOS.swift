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
    let albumContentRevision: Int
    let onRefresh: (() async -> Void)?

    init(
        albums: [PhotoAlbum],
        readOnlyMode: Bool,
        showsOnlyLocalAssets: Bool = false,
        albumContentRevision: Int = 0,
        onRefresh: (() async -> Void)? = nil
    ) {
        self.albums = albums
        self.readOnlyMode = readOnlyMode
        self.showsOnlyLocalAssets = showsOnlyLocalAssets
        self.albumContentRevision = albumContentRevision
        self.onRefresh = onRefresh
    }

    var body: some View {
        List(albums) { album in
            NavigationLink {
                AlbumDetailView(
                    album: album,
                    readOnlyMode: readOnlyMode,
                    showsOnlyLocalAssets: showsOnlyLocalAssets,
                    albumContentRevision: albumContentRevision
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
