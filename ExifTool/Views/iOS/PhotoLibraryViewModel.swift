#if os(iOS)

//
//  PhotoLibraryViewModel.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Foundation
import Observation
import Photos

@MainActor
@Observable
final class PhotoLibraryViewModel {
    enum LocalPhotosSummaryState: Equatable {
        case loading
        case paginating
        case buildingAlbums
        case complete
    }

    private static let localOnlyScanBatchSize = 48
    private static let localOnlyPageSize = 90
    private static let localOnlyPrefetchThreshold = 24
    private static let localOnlyAlbumRefreshInterval = 4

    enum AccessScope: Equatable {
        case unknown
        case limited
        case full
        case denied
    }
    
    enum AuthorizationState: Equatable {
        case unknown
        case limited
        case authorized
        case denied
        case empty
    }
    
    private(set) var accessScope: AccessScope = .unknown
    private(set) var authorizationState: AuthorizationState = .unknown
    private(set) var assets: [PhotoAsset] = []
    private(set) var albums: [PhotoAlbum] = []
    private(set) var localOnlyAssetIDs: Set<String> = []
    private(set) var showsOnlyLocalAssets = false
    private(set) var searchableAssetsRevision = 0
    private(set) var isFilteringLocalAssets = false
    private(set) var hasMoreLocalAssets = false
    private(set) var isBuildingLocalAlbumStats = false

    var searchableAssets: [PhotoAsset] {
        showsOnlyLocalAssets ? allFetchedAssets : assets
    }

    var localPhotosSummaryText: String? {
        guard showsOnlyLocalAssets else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        let localPhotoCount = formatter.string(from: NSNumber(value: localOnlyAssetIDs.count)) ?? "\(localOnlyAssetIDs.count)"
        let albumCount = formatter.string(from: NSNumber(value: albums.count)) ?? "\(albums.count)"

        if isFilteringLocalAssets && assets.isEmpty {
            return AppLocalization.string("localPhotos.loading")
        }
        if hasMoreLocalAssets {
            return AppLocalization.string("localPhotos.summary.more", localPhotoCount)
        }
        if isBuildingLocalAlbumStats {
            return AppLocalization.string("localPhotos.summary.buildingAlbums", localPhotoCount)
        }
        return AppLocalization.string("localPhotos.summary.complete", localPhotoCount, albumCount)
    }

    var localPhotosSummaryState: LocalPhotosSummaryState? {
        guard showsOnlyLocalAssets else {
            return nil
        }

        if isFilteringLocalAssets && assets.isEmpty {
            return .loading
        }
        if hasMoreLocalAssets {
            return .paginating
        }
        if isBuildingLocalAlbumStats {
            return .buildingAlbums
        }
        return .complete
    }

    var localPhotosCount: Int? {
        showsOnlyLocalAssets ? localOnlyAssetIDs.count : nil
    }

    var localAlbumsCount: Int? {
        showsOnlyLocalAssets ? albums.count : nil
    }

    var localPhotosSummarySnapshot: LocalPhotosStatusSnapshot? {
        guard let text = localPhotosSummaryText else {
            return nil
        }

        return LocalPhotosStatusSnapshot(
            text: text,
            state: localPhotosSummaryState,
            localPhotosCount: localPhotosCount,
            localAlbumsCount: localAlbumsCount
        )
    }

    var localPhotosPickerBannerSnapshot: LocalPhotosStatusSnapshot? {
        guard showsOnlyLocalAssets else {
            return nil
        }

        if isFilteringLocalAssets && assets.isEmpty {
            return LocalPhotosStatusSnapshot(
                text: AppLocalization.string("localPhotos.loading"),
                state: .loading,
                localPhotosCount: localPhotosCount,
                localAlbumsCount: nil
            )
        }

        if hasMoreLocalAssets {
            return LocalPhotosStatusSnapshot(
                text: AppLocalization.string("localPhotos.banner.more"),
                state: .paginating,
                localPhotosCount: localPhotosCount,
                localAlbumsCount: nil
            )
        }

        if isBuildingLocalAlbumStats {
            return LocalPhotosStatusSnapshot(
                text: AppLocalization.string("localPhotos.banner.buildingAlbums"),
                state: .buildingAlbums,
                localPhotosCount: localPhotosCount,
                localAlbumsCount: nil
            )
        }

        return nil
    }

    var localPhotosAlbumBannerSnapshot: LocalPhotosStatusSnapshot? {
        guard showsOnlyLocalAssets, isBuildingLocalAlbumStats else {
            return nil
        }

        return LocalPhotosStatusSnapshot(
            text: AppLocalization.string("localPhotos.albumBanner.buildingAlbums"),
            state: .buildingAlbums,
            localPhotosCount: localPhotosCount,
            localAlbumsCount: localAlbumsCount
        )
    }
    
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var albumStatsTask: Task<Void, Never>?
    private var allFetchedAssets: [PhotoAsset] = []
    @ObservationIgnored private var nextLocalOnlyScanIndex = 0
    @ObservationIgnored private var isLoadingNextLocalOnlyPage = false
    @ObservationIgnored private var localOnlySessionID = UUID()
    @ObservationIgnored private var localAvailabilityByID: [String: Bool] = [:]
    
    func prepare(showingOnlyLocalAssets: Bool) async {
        updateShowsOnlyLocalAssets(showingOnlyLocalAssets)
        await refresh()
    }
    
    func refresh() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        loadAssets(for: status)
    }

    func requestAccess(showingOnlyLocalAssets: Bool) async {
        updateShowsOnlyLocalAssets(showingOnlyLocalAssets)

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let newStatus: PHAuthorizationStatus
        if status == .notDetermined {
            newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            newStatus = status
        }

        loadAssets(for: newStatus)
    }

    func setShowsOnlyLocalAssets(_ enabled: Bool) async {
        updateShowsOnlyLocalAssets(enabled)
        await refresh()
    }
    
    private func loadAssets(for status: PHAuthorizationStatus) {
        refreshTask?.cancel()
        albumStatsTask?.cancel()
        localOnlySessionID = UUID()

        switch status {
        case .authorized:
            accessScope = .full
            authorizationState = .authorized
        case .limited:
            accessScope = .limited
            if authorizationState == .unknown {
                authorizationState = Self.fetchImageAssetCount() == 0 ? .empty : .limited
            } else if authorizationState != .empty {
                authorizationState = .limited
            }
        case .denied, .restricted:
            accessScope = .denied
            authorizationState = .denied
            resetLoadedContent()
            return
        case .notDetermined:
            accessScope = .unknown
            authorizationState = .unknown
            resetLoadedContent()
            return
        @unknown default:
            accessScope = .denied
            authorizationState = .denied
            resetLoadedContent()
            return
        }

        refreshTask = Task { [showsOnlyLocalAssets] in
            let fetchedAssets = await Self.fetchImageAssetsOffMain()
            self.allFetchedAssets = fetchedAssets

            if showsOnlyLocalAssets {
                self.markSearchableAssetsChanged()
                isFilteringLocalAssets = true
                self.nextLocalOnlyScanIndex = 0
                self.isLoadingNextLocalOnlyPage = false
                self.hasMoreLocalAssets = !fetchedAssets.isEmpty
                self.localOnlyAssetIDs = []
                self.assets = []
                self.albums = []
                self.isBuildingLocalAlbumStats = false
                self.authorizationState = authorizationStateForCurrentScope

                guard !fetchedAssets.isEmpty else {
                    self.authorizationState = .empty
                    self.isFilteringLocalAssets = false
                    self.hasMoreLocalAssets = false
                    return
                }
                
                await loadNextLocalOnlyPage(for: self.localOnlySessionID)
            } else {
                guard !Task.isCancelled else {
                    return
                }

                self.nextLocalOnlyScanIndex = fetchedAssets.count
                self.hasMoreLocalAssets = false
                self.localOnlyAssetIDs = Set(fetchedAssets.map(\.id))
                self.assets = fetchedAssets
                self.markSearchableAssetsChanged()
                self.albums = await Self.fetchImageAlbumsOffMain()
                self.isBuildingLocalAlbumStats = false
                self.authorizationState = fetchedAssets.isEmpty ? .empty : authorizationStateForCurrentScope
                self.isFilteringLocalAssets = false
            }
        }
    }
    
    nonisolated static func fetchImageAssets(in collection: PHAssetCollection? = nil) -> [PhotoAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let result: PHFetchResult<PHAsset>
        if let collection {
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }
        
        var fetchedAssets: [PhotoAsset] = []
        fetchedAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetchedAssets.append(PhotoAsset(asset: asset))
        }
        
        return fetchedAssets
    }

    nonisolated static func fetchImageAssetCount(in collection: PHAssetCollection? = nil) -> Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        if let collection {
            return PHAsset.fetchAssets(in: collection, options: options).count
        } else {
            return PHAsset.fetchAssets(with: options).count
        }
    }

    nonisolated static func fetchImageAssetsOffMain(in collection: PHAssetCollection? = nil) async -> [PhotoAsset] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let assets = Self.fetchImageAssets(in: collection)
                continuation.resume(returning: assets)
            }
        }
    }

    func loadMoreLocalAssetsIfNeeded(currentAssetID: String?) {
        guard showsOnlyLocalAssets, !isLoadingNextLocalOnlyPage, hasMoreLocalAssets else {
            return
        }

        if assets.isEmpty {
            Task {
                await loadNextLocalOnlyPage(for: localOnlySessionID)
            }
            return
        }

        guard let currentAssetID,
              let currentIndex = assets.firstIndex(where: { $0.id == currentAssetID }) else {
            return
        }

        let thresholdIndex = max(assets.count - Self.localOnlyPrefetchThreshold, 0)
        guard currentIndex >= thresholdIndex else {
            return
        }

        Task {
            await loadNextLocalOnlyPage(for: localOnlySessionID)
        }
    }

    func buildRemainingLocalAlbumStatsIfNeeded() {
        guard showsOnlyLocalAssets, !isBuildingLocalAlbumStats else {
            return
        }

        let sessionID = localOnlySessionID
        albumStatsTask?.cancel()
        albumStatsTask = Task { [weak self] in
            await self?.buildRemainingLocalAlbumStats(for: sessionID)
        }
    }
    
    private var authorizationStateForCurrentScope: AuthorizationState {
        switch accessScope {
        case .full:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .unknown:
            return .unknown
        }
    }

    private func resetLoadedContent() {
        albumStatsTask?.cancel()
        allFetchedAssets = []
        nextLocalOnlyScanIndex = 0
        isLoadingNextLocalOnlyPage = false
        assets = []
        albums = []
        localOnlyAssetIDs = []
        hasMoreLocalAssets = false
        isFilteringLocalAssets = false
        isBuildingLocalAlbumStats = false
        localAvailabilityByID = [:]
        markSearchableAssetsChanged()
    }

    private func updateShowsOnlyLocalAssets(_ enabled: Bool) {
        guard showsOnlyLocalAssets != enabled else {
            return
        }

        showsOnlyLocalAssets = enabled
        markSearchableAssetsChanged()
    }

    private func markSearchableAssetsChanged() {
        searchableAssetsRevision &+= 1
    }

    private func loadNextLocalOnlyPage(for sessionID: UUID) async {
        guard sessionID == localOnlySessionID, showsOnlyLocalAssets, !isLoadingNextLocalOnlyPage else {
            return
        }

        isLoadingNextLocalOnlyPage = true
        defer {
            isLoadingNextLocalOnlyPage = false
            isFilteringLocalAssets = false
        }

        var matchedAssets: [PhotoAsset] = []

        while matchedAssets.count < Self.localOnlyPageSize, nextLocalOnlyScanIndex < allFetchedAssets.count {
            let batchEnd = min(nextLocalOnlyScanIndex + Self.localOnlyScanBatchSize, allFetchedAssets.count)
            let assetBatch = Array(allFetchedAssets[nextLocalOnlyScanIndex..<batchEnd])
            nextLocalOnlyScanIndex = batchEnd

            let batchAssetIDs = await locallyAvailableIDs(in: assetBatch)
            guard !Task.isCancelled, sessionID == localOnlySessionID else {
                return
            }

            localOnlyAssetIDs.formUnion(batchAssetIDs)
            matchedAssets.append(contentsOf: assetBatch.filter { batchAssetIDs.contains($0.id) })
        }

        if !matchedAssets.isEmpty {
            assets.append(contentsOf: matchedAssets)
            albums = await Self.fetchImageAlbumsOffMain(filteringTo: localOnlyAssetIDs)
        }

        hasMoreLocalAssets = nextLocalOnlyScanIndex < allFetchedAssets.count
        authorizationState = assets.isEmpty && !hasMoreLocalAssets ? .empty : authorizationStateForCurrentScope
    }

    private func buildRemainingLocalAlbumStats(for sessionID: UUID) async {
        guard sessionID == localOnlySessionID, showsOnlyLocalAssets else {
            return
        }

        var scanIndex = nextLocalOnlyScanIndex
        guard scanIndex < allFetchedAssets.count else {
            isBuildingLocalAlbumStats = false
            return
        }

        isBuildingLocalAlbumStats = true
        defer { isBuildingLocalAlbumStats = false }

        var scannedBatchCount = 0

        while scanIndex < allFetchedAssets.count {
            let batchEnd = min(scanIndex + Self.localOnlyScanBatchSize, allFetchedAssets.count)
            let assetBatch = Array(allFetchedAssets[scanIndex..<batchEnd])
            scanIndex = batchEnd

            let batchAssetIDs = await locallyAvailableIDs(in: assetBatch)
            guard !Task.isCancelled, sessionID == localOnlySessionID else {
                return
            }

            localOnlyAssetIDs.formUnion(batchAssetIDs)
            scannedBatchCount += 1

            let shouldRefreshAlbums =
                scannedBatchCount.isMultiple(of: Self.localOnlyAlbumRefreshInterval) ||
                batchEnd == allFetchedAssets.count
            if shouldRefreshAlbums {
                albums = await Self.fetchImageAlbumsOffMain(filteringTo: localOnlyAssetIDs)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func locallyAvailableIDs(in assets: [PhotoAsset]) async -> Set<String> {
        var knownIDs = Set<String>()
        var unknownAssets: [PhotoAsset] = []
        unknownAssets.reserveCapacity(assets.count)

        for asset in assets {
            if let isLocal = localAvailabilityByID[asset.id] {
                if isLocal {
                    knownIDs.insert(asset.id)
                }
            } else {
                unknownAssets.append(asset)
            }
        }

        guard !unknownAssets.isEmpty else {
            return knownIDs
        }

        let resolvedLocalIDs = await PhotoLoader.locallyAvailableAssetIDs(from: unknownAssets)
        let resolvedLocalIDSet = Set(resolvedLocalIDs)

        for asset in unknownAssets {
            localAvailabilityByID[asset.id] = resolvedLocalIDSet.contains(asset.id)
        }

        knownIDs.formUnion(resolvedLocalIDSet)
        return knownIDs
    }

    nonisolated private static func fetchImageAlbumsOffMain(filteringTo assetIDs: Set<String>? = nil) async -> [PhotoAlbum] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let albums = Self.fetchImageAlbums(filteringTo: assetIDs)
                continuation.resume(returning: albums)
            }
        }
    }

    nonisolated private static func fetchImageAlbums(filteringTo assetIDs: Set<String>? = nil) -> [PhotoAlbum] {
        let imageOptions = PHFetchOptions()
        imageOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        var albums: [PhotoAlbum] = []
        var seenIdentifiers = Set<String>()
        
        func appendAlbums(from result: PHFetchResult<PHAssetCollection>) {
            result.enumerateObjects { collection, _, _ in
                guard !seenIdentifiers.contains(collection.localIdentifier) else {
                    return
                }
                
                let fetchedAssets = PHAsset.fetchAssets(in: collection, options: imageOptions)
                let count: Int
                if let assetIDs {
                    var matchedCount = 0
                    fetchedAssets.enumerateObjects { asset, _, _ in
                        if assetIDs.contains(asset.localIdentifier) {
                            matchedCount += 1
                        }
                    }
                    count = matchedCount
                } else {
                    count = fetchedAssets.count
                }

                guard count > 0 else {
                    return
                }
                
                seenIdentifiers.insert(collection.localIdentifier)
                albums.append(PhotoAlbum(collection: collection, assetCount: count))
            }
        }
        
        appendAlbums(from: PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil))
        appendAlbums(from: PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil))
        
        return albums.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}

#endif
