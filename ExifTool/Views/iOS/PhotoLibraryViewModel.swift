#if os(iOS)

//
//  PhotoLibraryViewModel.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Foundation
import Observation
import os
import Photos

@MainActor
@Observable
final class PhotoLibraryViewModel: NSObject {
    nonisolated private static func photoAsset(from asset: PHAsset) -> PhotoAsset {
        PhotoAsset(asset: asset)
    }
    private nonisolated struct PhotoAssetFetchSnapshot: @unchecked Sendable {
        let result: PHFetchResult<PHAsset>
        let assets: [PhotoAsset]
    }

    private nonisolated struct PhotoLibraryChange: @unchecked Sendable {
        let value: PHChange
    }

    private nonisolated struct PhotoAlbumMembershipIndex: @unchecked Sendable {
        let collections: [PHAssetCollection]
        let albumIDsByAssetID: [String: [String]]
    }

    enum LocalPhotosSummaryState: Equatable {
        case loading
        case paginating
        case buildingAlbums
        case complete
    }

    private static let localOnlyScanBatchSize = 48
    private static let localOnlyPageSize = 90
    private static let localOnlyPrefetchThreshold = 24

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
    private(set) var albumContentRevisions = CollectionRevisionIndex()
    private(set) var isFilteringLocalAssets = false
    private(set) var hasMoreLocalAssets = false
    private(set) var isBuildingLocalAlbumStats = false
    let localAvailabilityIndex = LocalAssetAvailabilityIndex()

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
    @ObservationIgnored private var albumMembershipTask: Task<PhotoAlbumMembershipIndex, Never>?
    @ObservationIgnored private var libraryChangeTask: Task<Void, Never>?
    @ObservationIgnored private var albumRefreshTask: Task<Void, Never>?
    @ObservationIgnored private let photoLibrary: PHPhotoLibrary
    @ObservationIgnored private var assetFetchResult: PHFetchResult<PHAsset>?
    @ObservationIgnored private var allFetchedAssets: [PhotoAsset] = []
    @ObservationIgnored private var nextLocalOnlyScanIndex = 0
    @ObservationIgnored private var isLoadingNextLocalOnlyPage = false
    @ObservationIgnored private var refreshGeneration = UUID()
    @ObservationIgnored private var localOnlySessionID = UUID()
    @ObservationIgnored private var localAlbumCountsByID: [String: Int] = [:]
    @ObservationIgnored private var countedLocalAssetIDs: Set<String> = []
    @ObservationIgnored private var hasRequestedLocalAlbumStats = false

    init(photoLibrary: PHPhotoLibrary = .shared()) {
        self.photoLibrary = photoLibrary
        super.init()
        photoLibrary.register(self)
    }

    deinit {
        photoLibrary.unregisterChangeObserver(self)
    }
    
    func prepare(showingOnlyLocalAssets: Bool) async {
        updateShowsOnlyLocalAssets(showingOnlyLocalAssets)
        await refresh()
    }
    
    func refresh() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let task = loadAssets(for: status)
        await task?.value
    }

    func applicationDidBecomeActive() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let expectedScope: AccessScope = switch status {
        case .authorized: .full
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .unknown
        @unknown default: .denied
        }
        if expectedScope != accessScope || assetFetchResult == nil {
            _ = loadAssets(for: status)
        }
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

        let task = loadAssets(for: newStatus)
        await task?.value
    }

    func setShowsOnlyLocalAssets(_ enabled: Bool) async {
        updateShowsOnlyLocalAssets(enabled)
        await refresh()
    }
    
    @discardableResult
    private func loadAssets(for status: PHAuthorizationStatus) -> Task<Void, Never>? {
        refreshTask?.cancel()
        albumStatsTask?.cancel()
        albumMembershipTask?.cancel()
        albumRefreshTask?.cancel()
        refreshGeneration = UUID()
        localOnlySessionID = refreshGeneration
        localAvailabilityIndex.invalidate()
        assetFetchResult = nil
        localAlbumCountsByID.removeAll(keepingCapacity: true)
        countedLocalAssetIDs.removeAll(keepingCapacity: true)
        let generation = refreshGeneration

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
            return nil
        case .notDetermined:
            accessScope = .unknown
            authorizationState = .unknown
            resetLoadedContent()
            return nil
        @unknown default:
            accessScope = .denied
            authorizationState = .denied
            resetLoadedContent()
            return nil
        }

        refreshTask = Task { [showsOnlyLocalAssets] in
            let snapshot = await Self.fetchImageAssetSnapshotOffMain()
            guard !Task.isCancelled, generation == self.refreshGeneration else {
                return
            }
            let fetchedAssets = snapshot.assets
            self.assetFetchResult = snapshot.result
            self.allFetchedAssets = fetchedAssets

            if showsOnlyLocalAssets {
                isFilteringLocalAssets = true
                self.nextLocalOnlyScanIndex = 0
                self.isLoadingNextLocalOnlyPage = false
                self.hasMoreLocalAssets = !fetchedAssets.isEmpty
                self.localOnlyAssetIDs = []
                self.assets = []
                self.albums = []
                self.isBuildingLocalAlbumStats = false
                self.hasRequestedLocalAlbumStats = false
                self.authorizationState = authorizationStateForCurrentScope

                guard !fetchedAssets.isEmpty else {
                    self.authorizationState = .empty
                    self.isFilteringLocalAssets = false
                    self.hasMoreLocalAssets = false
                    return
                }
                
                await loadNextLocalOnlyPage(for: generation)
            } else {
                self.nextLocalOnlyScanIndex = fetchedAssets.count
                self.hasMoreLocalAssets = false
                self.localOnlyAssetIDs = Set(fetchedAssets.map(\.id))
                self.assets = fetchedAssets
                let fetchedAlbums = await Self.fetchImageAlbumsOffMain()
                guard !Task.isCancelled, generation == self.refreshGeneration else {
                    return
                }
                self.albums = fetchedAlbums
                self.isBuildingLocalAlbumStats = false
                self.authorizationState = fetchedAssets.isEmpty ? .empty : authorizationStateForCurrentScope
                self.isFilteringLocalAssets = false
            }
        }
        return refreshTask
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
            fetchedAssets.append(photoAsset(from: asset))
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
        await PhotoLibraryQueryService.run { cancellation in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let result = collection.map { PHAsset.fetchAssets(in: $0, options: options) }
                ?? PHAsset.fetchAssets(with: options)
            var assets: [PhotoAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, stop in
                guard !cancellation.isCancelled else { stop.pointee = true; return }
                assets.append(photoAsset(from: asset))
            }
            return assets
        }
    }

    nonisolated private static func fetchImageAssetSnapshotOffMain() async -> PhotoAssetFetchSnapshot {
        await PhotoLibraryQueryService.run { cancellation in
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                let result = PHAsset.fetchAssets(with: options)
                var assets: [PhotoAsset] = []
                assets.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, stop in
                    guard !cancellation.isCancelled else { stop.pointee = true; return }
                    assets.append(photoAsset(from: asset))
                }
                return PhotoAssetFetchSnapshot(result: result, assets: assets)
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
        guard showsOnlyLocalAssets, !hasRequestedLocalAlbumStats, !isBuildingLocalAlbumStats else {
            return
        }

        hasRequestedLocalAlbumStats = true
        let sessionID = localOnlySessionID
        albumMembershipTask = Task {
            await Self.fetchPhotoAlbumMembershipIndexOffMain()
        }
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
        albumMembershipTask?.cancel()
        albumRefreshTask?.cancel()
        assetFetchResult = nil
        allFetchedAssets = []
        nextLocalOnlyScanIndex = 0
        isLoadingNextLocalOnlyPage = false
        assets = []
        albums = []
        localOnlyAssetIDs = []
        hasMoreLocalAssets = false
        isFilteringLocalAssets = false
        isBuildingLocalAlbumStats = false
        localAvailabilityIndex.invalidate()
        localAlbumCountsByID = [:]
        countedLocalAssetIDs = []
        hasRequestedLocalAlbumStats = false
    }

    private func updateShowsOnlyLocalAssets(_ enabled: Bool) {
        guard showsOnlyLocalAssets != enabled else {
            return
        }

        showsOnlyLocalAssets = enabled
    }

    private func scheduleLibraryChangeRefresh(_ change: PhotoLibraryChange) {
        libraryChangeTask?.cancel()
        libraryChangeTask = Task { [weak self] in
            guard let self, !Task.isCancelled else {
                return
            }
            self.applyLibraryChange(change.value)
        }
    }

    private func applyLibraryChange(_ change: PHChange) {
        let signpostID = PerformanceInstrumentation.signposter.makeSignpostID()
        let interval = PerformanceInstrumentation.signposter.beginInterval("ApplyPhotoLibraryChange", id: signpostID)
        defer { PerformanceInstrumentation.signposter.endInterval("ApplyPhotoLibraryChange", interval) }
        guard let assetFetchResult,
              let details = change.changeDetails(for: assetFetchResult) else {
            Task { await refresh() }
            return
        }

        let changedAlbumIDs = albums.compactMap { album in
            change.changeDetails(for: album.collection) == nil ? nil : album.id
        }
        refreshAlbumsAfterLibraryChange()

        guard details.hasIncrementalChanges else {
            Task { await refresh() }
            return
        }

        let updatedResult = details.fetchResultAfterChanges
        let insertedValues: [IndexedCollectionValue<PhotoAsset>] = (details.insertedIndexes ?? []).compactMap { index in
            guard index < updatedResult.count else { return nil }
            return IndexedCollectionValue(
                index: index,
                element: Self.photoAsset(from: updatedResult.object(at: index))
            )
        }
        var moves: [IndexedCollectionMove<String>] = []
        details.enumerateMoves { fromIndex, toIndex in
            guard fromIndex < assetFetchResult.count else { return }
            moves.append(
                IndexedCollectionMove(
                    id: assetFetchResult.object(at: fromIndex).localIdentifier,
                    destinationIndex: toIndex
                )
            )
        }
        let changedValues: [IndexedCollectionValue<PhotoAsset>] = (details.changedIndexes ?? []).compactMap { index in
            guard index < updatedResult.count else { return nil }
            return IndexedCollectionValue(
                index: index,
                element: Self.photoAsset(from: updatedResult.object(at: index))
            )
        }
        let updatedAssets = IndexedCollectionReducer.applying(
            to: allFetchedAssets,
            removedIndexes: Array(details.removedIndexes ?? []),
            insertedValues: insertedValues,
            moves: moves,
            changedValues: changedValues,
            id: \.id
        )
        self.assetFetchResult = updatedResult

        let removedIDs = Set(details.removedObjects.map(\.localIdentifier))
        let insertedIDs = Set(details.insertedObjects.map(\.localIdentifier))
        let changedIDs = Set(details.changedObjects.map(\.localIdentifier))
        guard !removedIDs.isEmpty || !insertedIDs.isEmpty || !changedIDs.isEmpty || !moves.isEmpty else {
            return
        }
        let affectedIDs = insertedIDs.union(changedIDs)

        if !changedAlbumIDs.isEmpty {
            albumContentRevisions.markChanged(changedAlbumIDs)
        } else if !insertedIDs.isEmpty || !removedIDs.isEmpty {
            // Photos normally reports the affected collections. Preserve correctness
            // if a provider only reports the asset-side membership change.
            albumContentRevisions.markChanged(albums.map(\.id))
        }

        allFetchedAssets = updatedAssets
        localAvailabilityIndex.invalidate(assetIDs: removedIDs.union(affectedIDs))
        localOnlyAssetIDs.subtract(removedIDs.union(affectedIDs))
        countedLocalAssetIDs.subtract(removedIDs.union(affectedIDs))

        guard showsOnlyLocalAssets else {
            assets = updatedAssets
            return
        }

        albumStatsTask?.cancel()
        albumMembershipTask?.cancel()
        albumMembershipTask = nil
        albums = []
        localAlbumCountsByID = [:]
        countedLocalAssetIDs = []
        hasRequestedLocalAlbumStats = false
        localOnlySessionID = UUID()
        isLoadingNextLocalOnlyPage = false

        let scannedCount = min(nextLocalOnlyScanIndex, updatedAssets.count)
        nextLocalOnlyScanIndex = scannedCount
        let scannedAssets = Array(updatedAssets.prefix(scannedCount))
        let sessionID = localOnlySessionID
        Task { [weak self] in
            guard let self else { return }
            let resolvedIDs = await self.localAvailabilityIndex.locallyAvailableIDs(in: scannedAssets)
            guard !Task.isCancelled, sessionID == self.localOnlySessionID else { return }
            self.localOnlyAssetIDs.formUnion(resolvedIDs)
            self.assets = scannedAssets.filter { self.localOnlyAssetIDs.contains($0.id) }
            self.hasMoreLocalAssets = scannedCount < updatedAssets.count
            self.authorizationState = self.assets.isEmpty && !self.hasMoreLocalAssets
                ? .empty
                : self.authorizationStateForCurrentScope
        }
    }

    private func refreshAlbumsAfterLibraryChange() {
        guard !showsOnlyLocalAssets else { return }
        albumRefreshTask?.cancel()
        albumRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let refreshedAlbums = await Self.fetchImageAlbumsOffMain()
            guard let self, !Task.isCancelled else { return }
            self.albums = refreshedAlbums
            self.albumContentRevisions.retainOnly(refreshedAlbums.map(\.id))
        }
    }

    private func loadNextLocalOnlyPage(for sessionID: UUID) async {
        guard sessionID == localOnlySessionID, showsOnlyLocalAssets, !isLoadingNextLocalOnlyPage else {
            return
        }

        isLoadingNextLocalOnlyPage = true
        defer {
            if sessionID == localOnlySessionID {
                isLoadingNextLocalOnlyPage = false
                isFilteringLocalAssets = false
            }
        }

        var matchedAssets: [PhotoAsset] = []
        while matchedAssets.count < Self.localOnlyPageSize, nextLocalOnlyScanIndex < allFetchedAssets.count {
            let batchEnd = min(nextLocalOnlyScanIndex + Self.localOnlyScanBatchSize, allFetchedAssets.count)
            let assetBatch = Array(allFetchedAssets[nextLocalOnlyScanIndex..<batchEnd])
            nextLocalOnlyScanIndex = batchEnd

            let batchAssetIDs = await locallyAvailableIDs(in: assetBatch, sessionID: sessionID)
            guard !Task.isCancelled, sessionID == localOnlySessionID else {
                return
            }

            localOnlyAssetIDs.formUnion(batchAssetIDs)
            matchedAssets.append(contentsOf: assetBatch.filter { batchAssetIDs.contains($0.id) })
        }

        if !matchedAssets.isEmpty {
            assets.append(contentsOf: matchedAssets)
        }
        hasMoreLocalAssets = nextLocalOnlyScanIndex < allFetchedAssets.count
        authorizationState = assets.isEmpty && !hasMoreLocalAssets ? .empty : authorizationStateForCurrentScope
    }

    private func buildRemainingLocalAlbumStats(for sessionID: UUID) async {
        guard sessionID == localOnlySessionID, showsOnlyLocalAssets else {
            return
        }

        isBuildingLocalAlbumStats = true
        defer {
            if sessionID == localOnlySessionID {
                isBuildingLocalAlbumStats = false
            }
        }

        await mergeLocalAlbumStats(for: localOnlyAssetIDs, sessionID: sessionID, publish: true)
        guard !Task.isCancelled, sessionID == localOnlySessionID else {
            return
        }

        var scanIndex = nextLocalOnlyScanIndex
        guard scanIndex < allFetchedAssets.count else {
            return
        }

        var scannedBatchCount = 0
        while scanIndex < allFetchedAssets.count {
            let batchEnd = min(scanIndex + Self.localOnlyScanBatchSize, allFetchedAssets.count)
            let assetBatch = Array(allFetchedAssets[scanIndex..<batchEnd])
            scanIndex = batchEnd

            let batchAssetIDs = await locallyAvailableIDs(in: assetBatch, sessionID: sessionID)
            guard !Task.isCancelled, sessionID == localOnlySessionID else {
                return
            }

            localOnlyAssetIDs.formUnion(batchAssetIDs)
            scannedBatchCount += 1
            let shouldPublish = scannedBatchCount.isMultiple(of: 4) || batchEnd == allFetchedAssets.count
            await mergeLocalAlbumStats(for: batchAssetIDs, sessionID: sessionID, publish: shouldPublish)
            guard !Task.isCancelled, sessionID == localOnlySessionID else {
                return
            }
            if shouldPublish {
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func locallyAvailableIDs(in assets: [PhotoAsset], sessionID: UUID) async -> Set<String> {
        let resolvedLocalIDs = await localAvailabilityIndex.locallyAvailableIDs(in: assets)
        guard !Task.isCancelled, sessionID == localOnlySessionID else {
            return []
        }
        return resolvedLocalIDs
    }

    private func mergeLocalAlbumStats(
        for assetIDs: Set<String>,
        sessionID: UUID,
        publish: Bool
    ) async {
        let uncountedAssetIDs = assetIDs.subtracting(countedLocalAssetIDs)
        guard !uncountedAssetIDs.isEmpty || publish else {
            return
        }

        let membershipIndex: PhotoAlbumMembershipIndex
        if let albumMembershipTask {
            membershipIndex = await albumMembershipTask.value
        } else {
            membershipIndex = await Self.fetchPhotoAlbumMembershipIndexOffMain()
        }
        guard !Task.isCancelled, sessionID == localOnlySessionID else {
            return
        }

        for assetID in uncountedAssetIDs {
            for albumID in membershipIndex.albumIDsByAssetID[assetID] ?? [] {
                localAlbumCountsByID[albumID, default: 0] += 1
            }
        }
        countedLocalAssetIDs.formUnion(uncountedAssetIDs)

        guard publish else {
            return
        }
        albums = membershipIndex.collections.compactMap { collection in
            let count = localAlbumCountsByID[collection.localIdentifier, default: 0]
            return count > 0 ? PhotoAlbum(collection: collection, assetCount: count) : nil
        }
        .sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    nonisolated private static func fetchPhotoAlbumMembershipIndexOffMain() async -> PhotoAlbumMembershipIndex {
        await PhotoLibraryQueryService.run { cancellation in
            fetchPhotoAlbumMembershipIndex(cancellation: cancellation)
        }
    }

    nonisolated private static func fetchPhotoAlbumMembershipIndex(
        cancellation: PhotoLibraryQueryCancellation
    ) -> PhotoAlbumMembershipIndex {
        let imageOptions = PHFetchOptions()
        imageOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        var collections: [PHAssetCollection] = []
        var seenCollectionIDs = Set<String>()
        var albumIDsByAssetID: [String: [String]] = [:]

        func appendCollections(from result: PHFetchResult<PHAssetCollection>) {
            result.enumerateObjects { collection, _, stop in
                guard !cancellation.isCancelled else { stop.pointee = true; return }
                let albumID = collection.localIdentifier
                guard seenCollectionIDs.insert(albumID).inserted else {
                    return
                }

                let fetchedAssets = PHAsset.fetchAssets(in: collection, options: imageOptions)
                guard fetchedAssets.count > 0 else {
                    return
                }
                collections.append(collection)
                fetchedAssets.enumerateObjects { asset, _, stop in
                    guard !cancellation.isCancelled else { stop.pointee = true; return }
                    albumIDsByAssetID[asset.localIdentifier, default: []].append(albumID)
                }
            }
        }

        appendCollections(from: PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil))
        appendCollections(from: PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil))
        return PhotoAlbumMembershipIndex(collections: collections, albumIDsByAssetID: albumIDsByAssetID)
    }

    nonisolated private static func fetchImageAlbumsOffMain() async -> [PhotoAlbum] {
        await PhotoLibraryQueryService.run { cancellation in
            Self.fetchImageAlbums(cancellation: cancellation)
        }
    }

    nonisolated private static func fetchImageAlbums(
        cancellation: PhotoLibraryQueryCancellation
    ) -> [PhotoAlbum] {
        let imageOptions = PHFetchOptions()
        imageOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        var albums: [PhotoAlbum] = []
        var seenIdentifiers = Set<String>()
        
        func appendAlbums(from result: PHFetchResult<PHAssetCollection>) {
            result.enumerateObjects { collection, _, stop in
                guard !cancellation.isCancelled else { stop.pointee = true; return }
                guard !seenIdentifiers.contains(collection.localIdentifier) else {
                    return
                }
                
                let fetchedAssets = PHAsset.fetchAssets(in: collection, options: imageOptions)
                let count = fetchedAssets.count

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

extension PhotoLibraryViewModel: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        let change = PhotoLibraryChange(value: changeInstance)
        Task { @MainActor [weak self] in
            self?.scheduleLibraryChangeRefresh(change)
        }
    }
}

#endif
