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
    @ObservationIgnored private var nextScanEndIndex = 0
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
        nextScanEndIndex = assets.count
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
        nextScanEndIndex = 0
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

        guard currentIndex < Self.prefetchThreshold else {
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

        while matchedAssets.count < Self.pageSize, nextScanEndIndex > 0 {
            let batchStart = max(nextScanEndIndex - Self.scanBatchSize, 0)
            let assetBatch = Array(sourceAssets[batchStart..<nextScanEndIndex])
            nextScanEndIndex = batchStart

            let localAssetIDs = await availabilityResolver(assetBatch)
            guard !Task.isCancelled, sessionID == self.sessionID else {
                return
            }

            matchedAssets.insert(
                contentsOf: assetBatch.filter { localAssetIDs.contains($0.id) },
                at: 0
            )
        }

        if !matchedAssets.isEmpty {
            assets.insert(contentsOf: matchedAssets, at: 0)
        }

        hasMoreAssets = nextScanEndIndex > 0
    }
}

#endif
