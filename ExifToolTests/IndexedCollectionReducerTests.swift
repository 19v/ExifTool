import XCTest
@testable import ExifTool

final class IndexedCollectionReducerTests: XCTestCase {
    private struct Item: Equatable {
        let id: String
        let value: Int
    }

    func testAppliesMixedRemovalInsertionMoveAndChangeInPhotosOrder() {
        let current = [
            Item(id: "a", value: 1),
            Item(id: "b", value: 2),
            Item(id: "c", value: 3),
            Item(id: "d", value: 4)
        ]

        let result = IndexedCollectionReducer.applying(
            to: current,
            removedIndexes: [1],
            insertedValues: [IndexedCollectionValue(index: 1, element: Item(id: "e", value: 5))],
            moves: [IndexedCollectionMove(id: "d", destinationIndex: 0)],
            changedValues: [IndexedCollectionValue(index: 1, element: Item(id: "a", value: 10))],
            id: \.id
        )

        XCTAssertEqual(
            result,
            [
                Item(id: "d", value: 4),
                Item(id: "a", value: 10),
                Item(id: "e", value: 5),
                Item(id: "c", value: 3)
            ]
        )
    }

    func testIgnoresInvalidIndexesAndMissingMoveIdentifiers() {
        let current = [Item(id: "a", value: 1), Item(id: "b", value: 2)]

        let result = IndexedCollectionReducer.applying(
            to: current,
            removedIndexes: [-1, 10],
            insertedValues: [IndexedCollectionValue(index: 9, element: Item(id: "c", value: 3))],
            moves: [IndexedCollectionMove(id: "missing", destinationIndex: 0)],
            changedValues: [IndexedCollectionValue(index: 4, element: Item(id: "a", value: 9))],
            id: \.id
        )

        XCTAssertEqual(result, current)
    }

    func testClampsMoveDestinationAfterRemovingTheMovedElement() {
        let current = [Item(id: "a", value: 1), Item(id: "b", value: 2)]

        let result = IndexedCollectionReducer.applying(
            to: current,
            removedIndexes: [],
            insertedValues: [],
            moves: [IndexedCollectionMove(id: "a", destinationIndex: 99)],
            changedValues: [],
            id: \.id
        )

        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }
}
