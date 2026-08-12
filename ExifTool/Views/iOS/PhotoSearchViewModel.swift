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
    @ObservationIgnored private var documents: [PhotoSearchDocument] = []
    @ObservationIgnored private var indexTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var filterTask: Task<[String], Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var indexGeneration = UUID()

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func setSourceAssets(_ assets: [PhotoAsset]) {
        indexTask?.cancel()
        debounceTask?.cancel()
        filterTask?.cancel()
        assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        publish(results.compactMap { assetsByID[$0.id] })
        documents = []

        let seeds = assets.map(PhotoSearchSeed.init)
        let currentIndexGeneration = UUID()
        indexGeneration = currentIndexGeneration
        if hasQuery {
            isSearching = true
        }
        indexTask = Task { [weak self] in
            let builtDocuments = await Task.detached(priority: .userInitiated) {
                seeds.map(PhotoSearchIndex.document)
            }.value

            guard let self, !Task.isCancelled, currentIndexGeneration == indexGeneration else {
                return
            }
            self.documents = builtDocuments
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
