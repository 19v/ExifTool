import Foundation

nonisolated struct CollectionRevisionIndex: Equatable, Sendable {
    private var revisions: [String: Int] = [:]

    subscript(id: String) -> Int {
        revisions[id, default: 0]
    }

    mutating func markChanged<S: Sequence>(_ ids: S) where S.Element == String {
        for id in Set(ids) {
            revisions[id, default: 0] &+= 1
        }
    }

    mutating func retainOnly<S: Sequence>(_ ids: S) where S.Element == String {
        let retainedIDs = Set(ids)
        revisions = revisions.filter { retainedIDs.contains($0.key) }
    }
}
