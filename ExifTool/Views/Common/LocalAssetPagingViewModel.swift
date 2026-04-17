//
//  LocalAssetPagingViewModel.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Combine
import Foundation

@MainActor
final class LocalAssetPagingViewModel: ObservableObject {
    private static let scanBatchSize = 48
    private static let pageSize = 90
    private static let prefetchThreshold = 24

    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var hasMoreAssets = false

    private var sourceAssets: [PhotoAsset] = []
    private var nextScanIndex = 0
    private var isLoading = false
    private var sessionID = UUID()

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
