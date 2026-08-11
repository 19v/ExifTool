import Foundation

nonisolated struct PhotoSearchDocument: Equatable, Sendable {
    let assetID: String
    let text: String
}

nonisolated enum PhotoSearchMatcher {
    static func matchingAssetIDs(
        query: String,
        documents: [PhotoSearchDocument]
    ) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        return documents.compactMap { document in
            guard !Task.isCancelled,
                  document.text.range(
                    of: trimmedQuery,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                  ) != nil else {
                return nil
            }
            return document.assetID
        }
    }
}
