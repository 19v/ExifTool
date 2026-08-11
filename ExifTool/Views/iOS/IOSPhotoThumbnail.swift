#if os(iOS)

//
//  PhotoThumbnail.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoThumbnail: View {
    let asset: PhotoAsset

    @Environment(\.displayScale) private var displayScale
    @State private var image: PlatformImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(Color.platformSecondaryBackground)

                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.width)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.width)
            .clipShape(Rectangle())
            .clipped()
            .task(id: thumbnailTaskID(width: proxy.size.width)) {
                guard proxy.size.width > 1 else {
                    return
                }

                let pixelLength = max(360, ceil(proxy.size.width * displayScale))
                image = await PhotoLoader.thumbnail(for: asset, size: CGSize(width: pixelLength, height: pixelLength))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("照片")
    }

    private func thumbnailTaskID(width: CGFloat) -> String {
        "\(asset.id)-\(Int(ceil(width * displayScale)))"
    }
}

#endif



