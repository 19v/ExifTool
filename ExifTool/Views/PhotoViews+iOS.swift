//
//  PhotoViews+iOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

import SwiftUI
import UIKit

extension Color {
    static var platformSecondaryBackground: Color {
        Color(.secondarySystemBackground)
    }
}

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    func platformDetailPagingStyle() -> some View {
        tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    @ViewBuilder
    func platformTabBarHidden() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

extension ToolbarItemPlacement {
    static var platformLanguageToggle: ToolbarItemPlacement {
        .topBarTrailing
    }
}

struct PlatformAlbumList: View {
    let albums: [PhotoAlbum]
    let readOnlyMode: Bool

    var body: some View {
        List(albums) { album in
            NavigationLink {
                AlbumDetailView(album: album, readOnlyMode: readOnlyMode)
            } label: {
                AlbumRowView(album: album)
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct PlatformSettingsImportSource: View {
    var body: some View {
        LabeledContent("图库", value: "系统照片库")
    }
}

struct PlatformPhotoGridScrollScrubber: View {
    var body: some View {
        EmptyView()
    }
}

#endif
