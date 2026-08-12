import XCTest
@testable import ExifTool

final class IncrementalUpdatePerformanceTests: XCTestCase {
    private struct Element: Equatable, Identifiable {
        let id: Int
        let value: Int
    }

    func testLargeCollectionIncrementalUpdatePerformance() {
        let source = (0..<100_000).map { Element(id: $0, value: $0) }
        let inserted = [IndexedCollectionValue(index: 50_000, element: Element(id: 100_000, value: 1))]
        let changed = [IndexedCollectionValue(index: 75_000, element: Element(id: 74_999, value: -1))]
        let moves = [IndexedCollectionMove(id: 5, destinationIndex: 90_000)]

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let result = IndexedCollectionReducer.applying(
                to: source,
                removedIndexes: [10],
                insertedValues: inserted,
                moves: moves,
                changedValues: changed,
                id: \.id
            )

            XCTAssertEqual(result.count, source.count)
            XCTAssertEqual(result[90_000].id, 5)
        }
    }
}
