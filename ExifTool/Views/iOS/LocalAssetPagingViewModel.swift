#if os(iOS)

//
//  LocalAssetPagingViewModel.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Foundation
import Observation

@MainActor
@Observable
final class LocalAssetPagingViewModel {
    private static let scanBatchSize = 48
    private static let pageSize = 90
    private static let prefetchThreshold = 24

    private(set) var assets: [PhotoAsset] = []
    private(set) var hasMoreAssets = false

    @ObservationIgnored private var sourceAssets: [PhotoAsset] = []
    @ObservationIgnored private var nextScanIndex = 0
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var sessionID = UUID()

    func setSourceAssets(_ assets: [PhotoAsset]) {
        sessionID = UUID()
        sourceAssets = assets
        nextScanIndex = 0
        self.assets = []
        hasMoreAssets = !assets.isEmpty

        guard !assets.isEmpty else {
            return
        }

        Task {
            await loadNextPage(for: sessionID)
        }
    }

    func reset() {
        sessionID = UUID()
        sourceAssets = []
        nextScanIndex = 0
        assets = []
        hasMoreAssets = false
        isLoading = false
    }

    func loadMoreIfNeeded(currentAssetID: String?) {
        guard !isLoading, hasMoreAssets else {
            return
        }

        if assets.isEmpty {
            Task {
                await loadNextPage(for: sessionID)
            }
            return
        }

        guard let currentAssetID,
              let currentIndex = assets.firstIndex(where: { $0.id == currentAssetID }) else {
            return
        }

        let thresholdIndex = max(assets.count - Self.prefetchThreshold, 0)
        guard currentIndex >= thresholdIndex else {
            return
        }

        Task {
            await loadNextPage(for: sessionID)
        }
    }

    private func loadNextPage(for sessionID: UUID) async {
        guard sessionID == self.sessionID, !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        var matchedAssets: [PhotoAsset] = []

        while matchedAssets.count < Self.pageSize, nextScanIndex < sourceAssets.count {
            let batchEnd = min(nextScanIndex + Self.scanBatchSize, sourceAssets.count)
            let assetBatch = Array(sourceAssets[nextScanIndex..<batchEnd])
            nextScanIndex = batchEnd

            let localAssetIDs = await PhotoLoader.locallyAvailableAssetIDs(from: assetBatch)
            guard !Task.isCancelled, sessionID == self.sessionID else {
                return
            }

            matchedAssets.append(contentsOf: assetBatch.filter { localAssetIDs.contains($0.id) })
        }

        if !matchedAssets.isEmpty {
            assets.append(contentsOf: matchedAssets)
        }

        hasMoreAssets = nextScanIndex < sourceAssets.count
    }
}

#endif
