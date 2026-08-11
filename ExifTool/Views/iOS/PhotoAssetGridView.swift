#if os(iOS)

//
//  PhotoAssetGridView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoAssetGridView: View {
    let assets: [PhotoAsset]
    let readOnlyMode: Bool
    let showsReadOnlyOverlay: Bool
    let isLoadingMore: Bool
    let onAssetAppear: ((String?) -> Void)?
    let onRefresh: (() async -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    init(
        assets: [PhotoAsset],
        readOnlyMode: Bool,
        showsReadOnlyOverlay: Bool = true,
        isLoadingMore: Bool = false,
        onAssetAppear: ((String?) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil
    ) {
        self.assets = assets
        self.readOnlyMode = readOnlyMode
        self.showsReadOnlyOverlay = showsReadOnlyOverlay
        self.isLoadingMore = isLoadingMore
        self.onAssetAppear = onAssetAppear
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(assets) { asset in
                    detailTrigger(for: asset)
                        .id(asset.id)
                        .onAppear {
                            onAssetAppear?(asset.id)
                        }
                }

                if isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .gridCellColumns(columns.count)
                }
            }
            .padding(3)
        }
        .refreshable {
            await onRefresh?()
        }
        .overlay(alignment: .bottom) {
            if showsReadOnlyOverlay && readOnlyMode {
                Text("只读模式已开启")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func detailTrigger(for asset: PhotoAsset) -> some View {
        NavigationLink {
            PhotoDetailView(
                assets: assets,
                initialAssetID: asset.id,
                readOnlyMode: readOnlyMode
            )
        } label: {
            PhotoThumbnail(asset: asset)
        }
        .buttonStyle(.plain)
    }
}

#endif
