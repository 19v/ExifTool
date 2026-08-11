#if os(iOS)

import Foundation
import Observation

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
    @ObservationIgnored private var indexedAssetsByID: [String: PhotoAsset] = [:]
    @ObservationIgnored private var indexedTextByAssetID: [String: String] = [:]
    @ObservationIgnored private var documents: [PhotoSearchDocument] = []
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var filterTask: Task<[String], Never>?
    @ObservationIgnored private var requestID = UUID()

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setSourceAssets(_ assets: [PhotoAsset]) {
        assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        publish(results.compactMap { assetsByID[$0.id] })

        let currentIDs = Set(assetsByID.keys)
        indexedAssetsByID = indexedAssetsByID.filter { currentIDs.contains($0.key) }
        indexedTextByAssetID = indexedTextByAssetID.filter { currentIDs.contains($0.key) }

        documents = assets.map { asset in
            if indexedAssetsByID[asset.id] != asset {
                indexedAssetsByID[asset.id] = asset
                indexedTextByAssetID[asset.id] = PhotoSearchIndex.text(for: asset)
            }

            return PhotoSearchDocument(
                assetID: asset.id,
                text: indexedTextByAssetID[asset.id] ?? ""
            )
        }

        scheduleSearch(debounced: false)
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
        if debounced {
            publish([])
        }
        let currentDocuments = documents

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

            let filterTask = Task.detached(priority: .userInitiated) {
                PhotoSearchMatcher.matchingAssetIDs(
                    query: trimmedQuery,
                    documents: currentDocuments
                )
            }
            self.filterTask = filterTask
            let matchingIDs = await filterTask.value

            guard !Task.isCancelled, currentRequestID == requestID else {
                return
            }

            self.publish(matchingIDs.compactMap { self.assetsByID[$0] })
            self.isSearching = false
        }
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
