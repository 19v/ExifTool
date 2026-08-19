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
    let isLoadingMore: Bool
    let sortOrder: PhotoAssetSortOrder
    let onAssetAppear: ((String?) -> Void)?
    let onRefresh: (() async -> Void)?

    @State private var thumbnailPreheater = PhotoThumbnailPreheater()
    @State private var positionedSortOrder: PhotoAssetSortOrder?
    @Environment(\.displayScale) private var displayScale

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    init(
        assets: [PhotoAsset],
        isLoadingMore: Bool = false,
        sortOrder: PhotoAssetSortOrder = .oldestFirst,
        onAssetAppear: ((String?) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil
    ) {
        self.assets = assets
        self.isLoadingMore = isLoadingMore
        self.sortOrder = sortOrder
        self.onAssetAppear = onAssetAppear
        self.onRefresh = onRefresh
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        if isLoadingMore && sortOrder == .oldestFirst {
                            PhotoGridLoadingIndicator(columnCount: columns.count)
                        }

                        ForEach(orderedAssets) { asset in
                            NavigationLink {
                                PhotoDetailView(
                                    assets: assets,
                                    initialAssetID: asset.id,
                                    sortOrder: sortOrder
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

                        if isLoadingMore && sortOrder == .newestFirst {
                            PhotoGridLoadingIndicator(columnCount: columns.count)
                        }
                    }
                    .padding(3)
                }
                .defaultScrollAnchor(initialScrollAnchor, for: .initialOffset)
                .onChange(of: initialPositionRevision, initial: true) { _, revision in
                    guard positionedSortOrder != revision.sortOrder,
                          let newestAssetID = revision.newestAssetID else {
                        return
                    }
                    positionedSortOrder = revision.sortOrder
                    Task { @MainActor in
                        await Task.yield()
                        scrollProxy.scrollTo(newestAssetID, anchor: initialScrollAnchor)
                    }
                }
                .refreshable {
                    await onRefresh?()
                }
                .platformTopScrollEdgeEffectHidden()
            }
        }
        .onDisappear {
            thumbnailPreheater.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            thumbnailPreheater.handleMemoryPressure()
        }
    }

    private func thumbnailPixelLength(containerWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 6
        let columnSpacing: CGFloat = 6
        let cellWidth = max(1, (containerWidth - horizontalPadding - columnSpacing) / CGFloat(columns.count))
        return ceil(cellWidth * displayScale)
    }

    private var orderedAssets: OrderedPhotoAssets {
        OrderedPhotoAssets(assets: assets, sortOrder: sortOrder)
    }

    private var initialScrollAnchor: UnitPoint {
        sortOrder == .oldestFirst ? .bottom : .top
    }

    private var initialPositionRevision: PhotoGridInitialPositionRevision {
        PhotoGridInitialPositionRevision(
            sortOrder: sortOrder,
            newestAssetID: assets.last?.id
        )
    }

}

private struct PhotoGridInitialPositionRevision: Equatable {
    let sortOrder: PhotoAssetSortOrder
    let newestAssetID: String?
}

private struct PhotoGridLoadingIndicator: View {
    let columnCount: Int

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .gridCellColumns(columnCount)
    }
}

private struct PhotoAssetGridCell: View {
    let asset: PhotoAsset

    var body: some View {
        PhotoThumbnail(asset: asset)
    }
}

#endif
