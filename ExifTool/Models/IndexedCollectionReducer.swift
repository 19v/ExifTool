import Foundation

nonisolated struct IndexedCollectionValue<Element> {
    let index: Int
    let element: Element
}

nonisolated struct IndexedCollectionMove<ID> {
    let id: ID
    let destinationIndex: Int
}

nonisolated enum IndexedCollectionReducer {
    static func applying<Element, ID: Equatable>(
        to current: [Element],
        removedIndexes: [Int],
        insertedValues: [IndexedCollectionValue<Element>],
        moves: [IndexedCollectionMove<ID>],
        changedValues: [IndexedCollectionValue<Element>],
        id: (Element) -> ID
    ) -> [Element] {
        var result = current

        for index in removedIndexes.sorted(by: >) where result.indices.contains(index) {
            result.remove(at: index)
        }

        for insertion in insertedValues.sorted(by: { $0.index < $1.index })
        where insertion.index >= 0 && insertion.index <= result.count {
            result.insert(insertion.element, at: insertion.index)
        }

        for move in moves {
            guard let currentIndex = result.firstIndex(where: { id($0) == move.id }) else {
                continue
            }
            let element = result.remove(at: currentIndex)
            let destinationIndex = min(max(move.destinationIndex, 0), result.count)
            result.insert(element, at: destinationIndex)
        }

        for change in changedValues where result.indices.contains(change.index) {
            result[change.index] = change.element
        }

        return result
    }
}
