#if os(iOS)

import XCTest
@testable import ExifTool

final class AsyncRequestLifecycleTests: XCTestCase {
    func testCancellationBeforeContinuationInstallationResumesWithCancellationValue() async {
        let state = CancellablePhotoRequestState<String, Int>(
            cancellationValue: "cancelled",
            cancelRequest: { _ in }
        )
        state.cancel()

        let value = await withCheckedContinuation { continuation in
            state.install(continuation)
        }

        XCTAssertEqual(value, "cancelled")
        XCTAssertTrue(state.isFinished)
        XCTAssertFalse(state.shouldStartRequest)
    }

    func testRegisteredRequestIsCancelledWhenTaskCancellationArrivesFirst() async {
        let cancelledToken = LockedValue<Int?>(nil)
        let state = CancellablePhotoRequestState<String, Int>(
            cancellationValue: "cancelled",
            cancelRequest: { token in cancelledToken.set(token) }
        )

        state.cancel()
        state.register(requestToken: 42)

        XCTAssertEqual(cancelledToken.value, 42)
    }

    func testCompletionBeforeContinuationInstallationReturnsCompletedValue() async {
        let state = CancellablePhotoRequestState<String, Int>(
            cancellationValue: "cancelled",
            cancelRequest: { _ in }
        )
        state.finish(returning: "finished")

        let value = await withCheckedContinuation { continuation in
            state.install(continuation)
        }

        XCTAssertEqual(value, "finished")
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func set(_ value: Value) {
        lock.withLock { storedValue = value }
    }
}

#endif
