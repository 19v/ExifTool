#if os(iOS)

import Foundation
import Observation
import os

@MainActor
@Observable
final class PhotoSearchViewModel {
    var query = "" {
        didSet {
            scheduleSearch(debounced: true)
        }
    }

    private(set) var results: [PhotoAsset] = []
    private(set) var resultsRevision = 0
    private(set) var isSearching = false

    @ObservationIgnored private var assetsByID: [String: PhotoAsset] = [:]
    @ObservationIgnored private var documentsByID: [String: PhotoSearchDocument] = [:]
    @ObservationIgnored private var orderedAssetIDs: [String] = []
    @ObservationIgnored private var fileNamesByID: [String: String] = [:]
    @ObservationIgnored private var resolvedFilenameIDs: Set<String> = []
    @ObservationIgnored private var indexTask: Task<Void, Never>?
    @ObservationIgnored private var filenameTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var filterTask: Task<[String], Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var indexGeneration = UUID()
    @ObservationIgnored private var indexRevision = 0
    @ObservationIgnored private var lastNormalizedQuery = ""
    @ObservationIgnored private var lastMatchingIDs: [String] = []
    @ObservationIgnored private var lastSearchIndexRevision = -1

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setSourceAssets(_ assets: [PhotoAsset]) {
        let signpostID = PerformanceInstrumentation.signposter.makeSignpostID()
        let interval = PerformanceInstrumentation.signposter.beginInterval("UpdateSearchIndex", id: signpostID)
        defer { PerformanceInstrumentation.signposter.endInterval("UpdateSearchIndex", interval) }
        indexTask?.cancel()
        filenameTask?.cancel()
        debounceTask?.cancel()
        filterTask?.cancel()
        let previousAssetsByID = assetsByID
        let newAssetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let changedAssets = assets.filter {
            documentsByID[$0.id] == nil || previousAssetsByID[$0.id] != $0
        }
        let removedIDs = Set(previousAssetsByID.keys).subtracting(newAssetsByID.keys)
        let invalidatedFilenameIDs = Set(changedAssets.compactMap { asset in
            previousAssetsByID[asset.id] == nil ? nil : asset.id
        })
        assetsByID = newAssetsByID
        orderedAssetIDs = assets.map(\.id)
        for removedID in removedIDs {
            documentsByID[removedID] = nil
            fileNamesByID[removedID] = nil
        }
        resolvedFilenameIDs.subtract(removedIDs.union(invalidatedFilenameIDs))
        for invalidatedID in invalidatedFilenameIDs {
            fileNamesByID[invalidatedID] = nil
        }
        invalidateNarrowingCache()
        publish(results.compactMap { assetsByID[$0.id] })

        let seeds = changedAssets.map { asset in
            PhotoSearchSeed(asset: asset, displayName: fileNamesByID[asset.id])
        }
        let currentIndexGeneration = UUID()
        indexGeneration = currentIndexGeneration
        if hasQuery {
            isSearching = true
        }
        indexTask = Task { [weak self] in
            let builtDocuments = await Task.detached(priority: .userInitiated) {
                let signpostID = PerformanceInstrumentation.signposter.makeSignpostID()
                let interval = PerformanceInstrumentation.signposter.beginInterval("BuildSearchDocuments", id: signpostID)
                defer { PerformanceInstrumentation.signposter.endInterval("BuildSearchDocuments", interval) }
                return Dictionary(uniqueKeysWithValues: seeds.map { seed in
                    let document = PhotoSearchIndex.document(for: seed)
                    return (document.assetID, document)
                })
            }.value

            guard let self, !Task.isCancelled, currentIndexGeneration == indexGeneration else {
                return
            }
            self.documentsByID.merge(builtDocuments) { _, updated in updated }
            self.indexRevision &+= 1
            self.scheduleSearch(debounced: false)
            self.resolveFilenamesIfNeeded(for: assets, generation: currentIndexGeneration)
        }
    }

    private func resolveFilenamesIfNeeded(for assets: [PhotoAsset], generation: UUID) {
        let unresolvedSeeds = assets.compactMap { asset -> PhotoLibraryFilenameSeed? in
            guard !resolvedFilenameIDs.contains(asset.id) else {
                return nil
            }
            return PhotoLibraryFilenameSeed(asset: asset)
        }
        guard !unresolvedSeeds.isEmpty else {
            return
        }

        filenameTask = Task { [weak self] in
            var resolvedNames: [String: String] = [:]
            let batchSize = 256
            var startIndex = unresolvedSeeds.startIndex

            while startIndex < unresolvedSeeds.endIndex {
                guard !Task.isCancelled else { return }
                let endIndex = min(startIndex + batchSize, unresolvedSeeds.endIndex)
                let batch = Array(unresolvedSeeds[startIndex..<endIndex])
                let batchNames = await PhotoLibraryFilenameResolver.resolve(batch)
                guard !Task.isCancelled else { return }
                resolvedNames.merge(batchNames) { _, updated in updated }
                startIndex = endIndex
                await Task.yield()
            }

            guard let self, !Task.isCancelled, generation == indexGeneration else {
                return
            }
            self.resolvedFilenameIDs.formUnion(unresolvedSeeds.map(\.assetID))
            self.fileNamesByID.merge(resolvedNames) { _, updated in updated }

            let renamedSeeds = unresolvedSeeds.compactMap { seed -> PhotoSearchSeed? in
                guard let asset = self.assetsByID[seed.assetID] else {
                    return nil
                }
                return PhotoSearchSeed(asset: asset, displayName: resolvedNames[seed.assetID])
            }
            let renamedDocuments = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: renamedSeeds.map { seed in
                    let document = PhotoSearchIndex.document(for: seed)
                    return (document.assetID, document)
                })
            }.value
            guard !Task.isCancelled, generation == self.indexGeneration else {
                return
            }
            self.documentsByID.merge(renamedDocuments) { _, updated in updated }
            self.indexRevision &+= 1
            self.invalidateNarrowingCache()
            self.scheduleSearch(debounced: false)
        }
    }

    private func scheduleSearch(debounced: Bool) {
        debounceTask?.cancel()
        filterTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            requestID = UUID()
            isSearching = false
            publish([])
            return
        }

        let currentRequestID = UUID()
        requestID = currentRequestID
        isSearching = true
        let normalizedQuery = PhotoSearchMatcher.normalized(trimmedQuery)

        debounceTask = Task { [weak self] in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }

            guard let self, !Task.isCancelled, currentRequestID == requestID else {
                return
            }

            let canNarrowPreviousResults = self.lastSearchIndexRevision == self.indexRevision &&
                !self.lastNormalizedQuery.isEmpty &&
                normalizedQuery.hasPrefix(self.lastNormalizedQuery)
            let candidateIDs = canNarrowPreviousResults
                ? self.lastMatchingIDs
                : self.orderedAssetIDs
            let currentDocuments = candidateIDs.compactMap { self.documentsByID[$0] }
            let currentIndexRevision = self.indexRevision

            let filterTask = Task.detached(priority: .userInitiated) {
                PhotoSearchMatcher.matchingAssetIDs(
                    normalizedQuery: normalizedQuery,
                    documents: currentDocuments
                )
            }
            self.filterTask = filterTask
            let matchingIDs = await filterTask.value

            guard !Task.isCancelled, currentRequestID == requestID else {
                return
            }

            self.publish(matchingIDs.compactMap { self.assetsByID[$0] })
            self.lastNormalizedQuery = normalizedQuery
            self.lastMatchingIDs = matchingIDs
            self.lastSearchIndexRevision = currentIndexRevision
            self.isSearching = false
        }
    }

    private func invalidateNarrowingCache() {
        lastNormalizedQuery = ""
        lastMatchingIDs = []
        lastSearchIndexRevision = -1
    }

    private func publish(_ newResults: [PhotoAsset]) {
        guard results != newResults else {
            return
        }

        results = newResults
        resultsRevision &+= 1
    }
}

#endif
