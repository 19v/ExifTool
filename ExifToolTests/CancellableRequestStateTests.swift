import Foundation
import XCTest
@testable import ExifTool

final class CancellableRequestStateTests: XCTestCase {
    func testCancellationResumesInstalledContinuationAndCancelsRegisteredRequest() async {
        let recorder = CancelledTokenRecorder()
        let state = CancellablePhotoRequestState<Result<String, Error>, Int>(
            cancellationValue: .failure(CancellationError()),
            cancelRequest: recorder.record
        )
        let resultTask = Task {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                state.register(requestToken: 42)
            }
        }
        await Task.yield()

        state.cancel()
        let result = await resultTask.value

        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(recorder.tokens, [42])
    }

    func testCancellationBeforeInstallResumesContinuationWhenInstalled() async {
        let recorder = CancelledTokenRecorder()
        let state = CancellablePhotoRequestState<Result<String, Error>, Int>(
            cancellationValue: .failure(CancellationError()),
            cancelRequest: recorder.record
        )
        state.cancel()

        let result: Result<String, Error> = await withCheckedContinuation { continuation in
            state.install(continuation)
        }

        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(state.shouldStartRequest)
    }

    func testWriteFailureFinishesPromptlyAndIgnoresLateFrameworkCompletion() async {
        enum TestError: Error { case write, framework }
        let recorder = CancelledTokenRecorder()
        let state = CancellablePhotoRequestState<Result<String, Error>, Int>(
            cancellationValue: .failure(CancellationError()),
            cancelRequest: recorder.record
        )
        let resultTask = Task {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                state.register(requestToken: 7)
            }
        }
        await Task.yield()

        state.finish(returning: .failure(TestError.write), cancellingRequest: true)
        state.finish(returning: .failure(TestError.framework))
        let result = await resultTask.value

        XCTAssertThrowsError(try result.get()) { error in
            guard case TestError.write = error else {
                return XCTFail("Expected the original write error")
            }
        }
        XCTAssertEqual(recorder.tokens, [7])
    }
}

private final class CancelledTokenRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedTokens: [Int] = []

    var tokens: [Int] {
        lock.withLock { recordedTokens }
    }

    func record(_ token: Int) {
        lock.withLock { recordedTokens.append(token) }
    }
}
