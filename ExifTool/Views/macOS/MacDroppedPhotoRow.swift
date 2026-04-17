//
//  MacDroppedPhotoRow.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import SwiftUI

struct MacDroppedPhotoRow: View {
    let asset: PhotoAsset

    var body: some View {
        HStack(spacing: 10) {
            PhotoThumbnail(asset: asset)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.displayName ?? "照片")
                    .font(.headline)
                    .lineLimit(1)

                Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#endif
