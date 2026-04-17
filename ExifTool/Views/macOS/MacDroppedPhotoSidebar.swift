//
//  MacDroppedPhotoSidebar.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import SwiftUI

struct MacDroppedPhotoSidebar: View {
    let assets: [PhotoAsset]
    @Binding var selectedAssetID: String?

    var body: some View {
        List(assets, selection: $selectedAssetID) { asset in
            MacDroppedPhotoRow(asset: asset)
                .tag(asset.id)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }
}

#endif
