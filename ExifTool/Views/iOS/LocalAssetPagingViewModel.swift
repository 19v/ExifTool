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
    typealias AvailabilityResolver = @MainActor ([PhotoAsset]) async -> Set<String>

    private static let scanBatchSize = 48
    private static let pageSize = 90
    private static let prefetchThreshold = 24

    private(set) var assets: [PhotoAsset] = []
    private(set) var hasMoreAssets = false

    @ObservationIgnored private var sourceAssets: [PhotoAsset] = []
    @ObservationIgnored private var nextScanIndex = 0
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let availabilityResolver: AvailabilityResolver

    init(availabilityResolver: @escaping AvailabilityResolver = PhotoLoader.locallyAvailableAssetIDs) {
        self.availabilityResolver = availabilityResolver
    }

    func setSourceAssets(_ assets: [PhotoAsset]) {
        loadTask?.cancel()
        sessionID = UUID()
        sourceAssets = assets
        nextScanIndex = 0
        isLoading = false
        self.assets = []
        hasMoreAssets = !assets.isEmpty

        guard !assets.isEmpty else {
            return
        }

        startLoadingNextPage()
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
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
            startLoadingNextPage()
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

        startLoadingNextPage()
    }

    private func startLoadingNextPage() {
        let currentSessionID = sessionID
        loadTask = Task { [weak self] in
            await self?.loadNextPage(for: currentSessionID)
        }
    }

    private func loadNextPage(for sessionID: UUID) async {
        guard sessionID == self.sessionID, !isLoading else {
            return
        }

        isLoading = true
        defer {
            if sessionID == self.sessionID {
                isLoading = false
            }
        }

        var matchedAssets: [PhotoAsset] = []

        while matchedAssets.count < Self.pageSize, nextScanIndex < sourceAssets.count {
            let batchEnd = min(nextScanIndex + Self.scanBatchSize, sourceAssets.count)
            let assetBatch = Array(sourceAssets[nextScanIndex..<batchEnd])
            nextScanIndex = batchEnd

            let localAssetIDs = await availabilityResolver(assetBatch)
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
