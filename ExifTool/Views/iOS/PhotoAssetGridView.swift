#if os(iOS)

//
//  PhotoAssetGridView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI
import UIKit

struct PhotoAssetGridView: View {
    let assets: [PhotoAsset]
    let readOnlyMode: Bool
    let showsReadOnlyOverlay: Bool
    let isLoadingMore: Bool
    let onAssetAppear: ((String?) -> Void)?
    let onRefresh: (() async -> Void)?

    @State private var thumbnailPreheater = PhotoThumbnailPreheater()
    @Environment(\.displayScale) private var displayScale

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
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(assets) { asset in
                        NavigationLink {
                            PhotoDetailView(
                                assets: assets,
                                initialAssetID: asset.id,
                                readOnlyMode: readOnlyMode
                            )
                        } label: {
                            PhotoAssetGridCell(asset: asset)
                        }
                        .buttonStyle(.plain)
                        .id(asset.id)
                            .onAppear {
                                onAssetAppear?(asset.id)
                                thumbnailPreheater.update(
                                    around: asset.id,
                                    in: assets,
                                    pixelLength: thumbnailPixelLength(containerWidth: proxy.size.width)
                                )
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
        }
        .onDisappear {
            thumbnailPreheater.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            thumbnailPreheater.handleMemoryPressure()
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

    private func thumbnailPixelLength(containerWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 6
        let columnSpacing: CGFloat = 6
        let cellWidth = max(1, (containerWidth - horizontalPadding - columnSpacing) / CGFloat(columns.count))
        return ceil(cellWidth * displayScale)
    }

}

private struct PhotoAssetGridCell: View {
    let asset: PhotoAsset

    var body: some View {
        PhotoThumbnail(asset: asset)
    }
}

#endif
