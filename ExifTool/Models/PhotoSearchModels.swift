import Foundation

nonisolated struct PhotoSearchDocument: Equatable, Sendable {
    let assetID: String
    let text: String
    let normalizedText: String

    init(assetID: String, text: String) {
        self.assetID = assetID
        self.text = text
        self.normalizedText = PhotoSearchMatcher.normalized(text)
    }
}

nonisolated enum PhotoSearchMatcher {
    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
    }

    static func matchingAssetIDs(
        query: String,
        documents: [PhotoSearchDocument]
    ) -> [String] {
        matchingAssetIDs(normalizedQuery: normalized(query), documents: documents)
    }

    static func matchingAssetIDs(
        normalizedQuery: String,
        documents: [PhotoSearchDocument]
    ) -> [String] {
        guard !normalizedQuery.isEmpty else {
            return []
        }

        return documents.compactMap { document in
            guard !Task.isCancelled,
                  document.normalizedText.contains(normalizedQuery) else {
                return nil
            }
            return document.assetID
        }
    }
}
