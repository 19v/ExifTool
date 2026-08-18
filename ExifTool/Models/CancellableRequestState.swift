import Foundation

nonisolated final class CancellablePhotoRequestState<Value: Sendable, RequestToken: Sendable>: @unchecked Sendable {
    private enum Completion {
        case pending
        case finished(Value)
    }

    private let lock = NSLock()
    private let cancellationValue: Value
    private let cancelRequest: @Sendable (RequestToken) -> Void
    nonisolated(unsafe) private var completion: Completion = .pending
    nonisolated(unsafe) private var continuation: CheckedContinuation<Value, Never>?
    nonisolated(unsafe) private var requestToken: RequestToken?
    nonisolated(unsafe) private var cancellationRequested = false

    init(
        cancellationValue: Value,
        cancelRequest: @escaping @Sendable (RequestToken) -> Void
    ) {
        self.cancellationValue = cancellationValue
        self.cancelRequest = cancelRequest
    }

    var shouldStartRequest: Bool {
        lock.withLock {
            if case .pending = completion {
                return true
            }
            return false
        }
    }

    var isFinished: Bool {
        lock.withLock {
            if case .finished = completion {
                return true
            }
            return false
        }
    }

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        let completedValue: Value? = lock.withLock {
            switch completion {
            case .pending:
                self.continuation = continuation
                return nil
            case .finished(let value):
                return value
            }
        }
        if let completedValue {
            continuation.resume(returning: completedValue)
        }
    }

    func register(requestToken: RequestToken) {
        let shouldCancel = lock.withLock {
            self.requestToken = requestToken
            return cancellationRequested
        }
        if shouldCancel {
            cancelRequest(requestToken)
        }
    }

    func finish(returning value: Value, cancellingRequest shouldCancelRequest: Bool = false) {
        let completionResult: (CheckedContinuation<Value, Never>?, RequestToken?)? = lock.withLock {
            guard case .pending = completion else {
                return nil
            }
            if shouldCancelRequest {
                cancellationRequested = true
            }
            completion = .finished(value)
            let continuationToResume = continuation
            continuation = nil
            return (continuationToResume, shouldCancelRequest ? requestToken : nil)
        }
        guard let completionResult else {
            return
        }
        if let requestToken = completionResult.1 {
            cancelRequest(requestToken)
        }
        completionResult.0?.resume(returning: value)
    }

    func cancel() {
        let cancellationResult: (CheckedContinuation<Value, Never>?, RequestToken?)? = lock.withLock {
            guard case .pending = completion else {
                return nil
            }
            cancellationRequested = true
            completion = .finished(cancellationValue)
            let continuationToResume = continuation
            continuation = nil
            return (continuationToResume, requestToken)
        }
        guard let cancellationResult else {
            return
        }
        if let requestToken = cancellationResult.1 {
            cancelRequest(requestToken)
        }
        cancellationResult.0?.resume(returning: cancellationValue)
    }
}
