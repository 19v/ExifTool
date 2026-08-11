#if os(iOS)

//
//  PhotoPreview.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoPreview: View {
    let asset: PhotoAsset

    @State private var image: PlatformImage?
    @State private var previewRequestID = UUID()

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .background(Color.platformSecondaryBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: asset.id) {
            let requestID = UUID()
            previewRequestID = requestID
            image = nil
            let newImage = await PhotoLoader.previewImage(
                for: asset,
                size: CGSize(width: 900, height: 900)
            )
            guard !Task.isCancelled, requestID == previewRequestID else {
                return
            }

            image = newImage
        }
    }
}

#endif


