#if os(iOS)

import Foundation
import Photos

nonisolated final class PhotoLibraryQueryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

nonisolated enum PhotoLibraryQueryService {
    static func run<Value: Sendable>(
        _ operation: @escaping @Sendable (PhotoLibraryQueryCancellation) -> Value
    ) async -> Value {
        let cancellation = PhotoLibraryQueryCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: operation(cancellation))
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

#endif
