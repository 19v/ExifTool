#if os(iOS)

//
//  PhotoPreview.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoPreview: View {
    let image: PlatformImage?

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
    }
}

#endif

