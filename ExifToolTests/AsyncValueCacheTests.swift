import Foundation
import XCTest
@testable import ExifTool

final class AsyncValueCacheTests: XCTestCase {
    func testConcurrentConsumersShareOneOperation() async throws {
        let cache = AsyncValueCache<String, Int>()
        let counter = InvocationCounter()

        async let first = cache.value(for: "photo") {
            counter.increment()
            try await Task.sleep(for: .milliseconds(40))
            return 42
        }
        async let second = cache.value(for: "photo") {
            counter.increment()
            return 99
        }

        let values = try await [first, second]
        XCTAssertEqual(values[0], values[1])
        XCTAssertTrue(values[0] == 42 || values[0] == 99)
        XCTAssertEqual(counter.value, 1)
    }

    func testCompletedValueIsReusedUntilRemoved() async throws {
        let cache = AsyncValueCache<String, Int>()
        let counter = InvocationCounter()
        let first = try await cache.value(for: "photo") {
            counter.increment()
            return 1
        }
        let second = try await cache.value(for: "photo") {
            counter.increment()
            return 2
        }

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        XCTAssertEqual(counter.value, 1)

        await cache.removeValue(for: "photo")
        let third = try await cache.value(for: "photo") {
            counter.increment()
            return 3
        }
        XCTAssertEqual(third, 3)
        XCTAssertEqual(counter.value, 2)
    }

    func testFailureIsNotCached() async throws {
        enum ExpectedError: Error { case failed }
        let cache = AsyncValueCache<String, Int>()
        let counter = InvocationCounter()

        do {
            _ = try await cache.value(for: "photo") {
                counter.increment()
                throw ExpectedError.failed
            }
            XCTFail("Expected the first operation to fail")
        } catch ExpectedError.failed { }

        let recovered = try await cache.value(for: "photo") {
            counter.increment()
            return 7
        }
        XCTAssertEqual(recovered, 7)
        XCTAssertEqual(counter.value, 2)
    }

    func testCancelledConsumerReturnsPromptlyWithoutCancellingSharedOperation() async throws {
        let cache = AsyncValueCache<String, Int>()
        let counter = InvocationCounter()
        let operationStarted = expectation(description: "operation started")
        let consumerFinished = expectation(description: "cancelled consumer finished")
        let consumer = Task {
            try await cache.value(for: "photo") {
                counter.increment()
                operationStarted.fulfill()
                try await Task.sleep(for: .milliseconds(300))
                return 7
            }
        }
        await fulfillment(of: [operationStarted], timeout: 1)

        consumer.cancel()
        Task {
            let result = await consumer.result
            if case .failure(let error) = result {
                XCTAssertTrue(error is CancellationError)
            } else {
                XCTFail("Expected cancelled consumer to fail")
            }
            consumerFinished.fulfill()
        }
        await fulfillment(of: [consumerFinished], timeout: 0.2)

        let reusedValue = try await cache.value(for: "photo") { 99 }
        XCTAssertEqual(reusedValue, 7)
        XCTAssertEqual(counter.value, 1)
    }
}

private final class InvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}
