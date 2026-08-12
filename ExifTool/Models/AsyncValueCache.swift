import Foundation

actor AsyncValueCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let id: UUID
        let task: Task<Value, Error>
    }

    private var entries: [Key: Entry] = [:]

    func value(
        for key: Key,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let entry = entries[key] {
            return try await waitForValue(of: entry, key: key)
        }

        let entry = Entry(id: UUID(), task: Task { try await operation() })
        entries[key] = entry
        return try await waitForValue(of: entry, key: key)
    }

    private func waitForValue(of entry: Entry, key: Key) async throws -> Value {
        do {
            return try await cancellableValue(of: entry.task)
        } catch {
            if error is CancellationError, Task.isCancelled {
                throw error
            }
            if entries[key]?.id == entry.id {
                entries[key] = nil
            }
            throw error
        }
    }

    private func cancellableValue(of task: Task<Value, Error>) async throws -> Value {
        let state = CancellablePhotoRequestState<Result<Value, Error>, Void>(
            cancellationValue: .failure(CancellationError()),
            cancelRequest: { _ in }
        )
        let result: Result<Value, Error> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                guard state.shouldStartRequest else { return }
                Task {
                    do {
                        state.finish(returning: .success(try await task.value))
                    } catch {
                        state.finish(returning: .failure(error))
                    }
                }
            }
        } onCancel: {
            state.cancel()
        }
        return try result.get()
    }

    func removeValue(for key: Key) {
        entries[key]?.task.cancel()
        entries[key] = nil
    }

    func removeAll() {
        for entry in entries.values {
            entry.task.cancel()
        }
        entries.removeAll()
    }
}
