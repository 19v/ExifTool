#if os(iOS)

import Foundation

@MainActor
final class LocalAssetAvailabilityIndex {
    private struct InFlightResolution {
        let token: UUID
        let assetIDs: Set<String>
        let task: Task<Set<String>, Never>
    }

    private var availabilityByID: [String: Bool] = [:]
    private var inFlightByID: [String: InFlightResolution] = [:]

    func locallyAvailableIDs(in assets: [PhotoAsset]) async -> Set<String> {
        var localIDs = Set<String>()
        var resolutionsByToken: [UUID: InFlightResolution] = [:]
        var unresolvedAssets: [PhotoAsset] = []

        for asset in assets {
            if let isLocal = availabilityByID[asset.id] {
                if isLocal {
                    localIDs.insert(asset.id)
                }
            } else if let resolution = inFlightByID[asset.id] {
                resolutionsByToken[resolution.token] = resolution
            } else {
                unresolvedAssets.append(asset)
            }
        }

        if !unresolvedAssets.isEmpty {
            let token = UUID()
            let assetIDs = Set(unresolvedAssets.map(\.id))
            let task = Task {
                await PhotoLoader.locallyAvailableAssetIDs(from: unresolvedAssets)
            }
            let resolution = InFlightResolution(token: token, assetIDs: assetIDs, task: task)
            for assetID in assetIDs {
                inFlightByID[assetID] = resolution
            }
            resolutionsByToken[token] = resolution
        }

        for resolution in resolutionsByToken.values {
            let resolvedLocalIDs = await resolution.task.value
            guard !Task.isCancelled else {
                return localIDs
            }

            for assetID in resolution.assetIDs {
                guard inFlightByID[assetID]?.token == resolution.token else {
                    continue
                }
                availabilityByID[assetID] = resolvedLocalIDs.contains(assetID)
                inFlightByID[assetID] = nil
            }
            localIDs.formUnion(resolvedLocalIDs)
        }

        return localIDs.intersection(assets.lazy.map(\.id))
    }

    func invalidate() {
        let tasksByToken = Dictionary(
            inFlightByID.values.map { ($0.token, $0.task) },
            uniquingKeysWith: { first, _ in first }
        )
        for task in tasksByToken.values {
            task.cancel()
        }
        inFlightByID.removeAll(keepingCapacity: true)
        availabilityByID.removeAll(keepingCapacity: true)
    }
}

#endif
