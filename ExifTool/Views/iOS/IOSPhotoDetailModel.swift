#if os(iOS)

import Foundation
import Observation

@MainActor
@Observable
final class IOSPhotoDetailModel {
    private(set) var detail = PhotoDetailState.loading
    private(set) var isDownloadingOriginal = false
    private(set) var resolvedDisplayName: String?
    var showsICloudDownloadExplanation = false
    var activityShareItem: ActivityShareItem?
    private(set) var isPreparingPhotoShare = false
    var shareErrorMessage: String?

    @ObservationIgnored private var metadataRequestID = UUID()

    var loadedMetadata: PhotoMetadata? {
        guard case .loaded(let metadata) = detail else {
            return nil
        }
        return metadata
    }

    var isShareErrorPresented: Bool {
        get { shareErrorMessage != nil }
        set {
            if !newValue {
                shareErrorMessage = nil
            }
        }
    }

    func loadMetadata(for asset: PhotoAsset, allowNetwork: Bool) async {
        let requestID = UUID()
        metadataRequestID = requestID

        if allowNetwork {
            isDownloadingOriginal = true
        } else {
            detail = .loading
            isDownloadingOriginal = false
        }

        async let detailResult = PhotoLoader.metadata(for: asset, allowNetwork: allowNetwork)
        async let displayName = PhotoLoader.displayName(for: asset)
        let (newDetail, newDisplayName) = await (detailResult, displayName)
        guard !Task.isCancelled, requestID == metadataRequestID else {
            return
        }

        detail = newDetail
        resolvedDisplayName = newDisplayName
        isDownloadingOriginal = false
    }

    func sharePhoto(asset: PhotoAsset, allowsICloudDownload: Bool) async {
        isPreparingPhotoShare = true
        defer { isPreparingPhotoShare = false }

        do {
            let url = try await PhotoLoader.shareablePhotoURL(
                for: asset,
                allowNetwork: allowsICloudDownload
            )
            guard !Task.isCancelled else {
                return
            }
            activityShareItem = ActivityShareItem(
                items: [url],
                cleanupURL: PhotoTemporaryFileStore.isShareFile(url) ? url : nil
            )
        } catch {
            guard !Task.isCancelled else {
                return
            }
            shareErrorMessage = allowsICloudDownload
                ? error.localizedDescription
                : AppLocalization.string("photoDetail.shareNeedsDownload")
        }
    }

    func shareParameters(
        asset: PhotoAsset,
        showsChineseKeys: Bool,
        visibleMetadataKeys: Set<String>?
    ) {
        guard let metadata = loadedMetadata else {
            shareErrorMessage = AppLocalization.string("photoDetail.shareParametersNotReady")
            return
        }

        let text = MetadataShareFormatter.text(
            for: asset,
            displayName: resolvedDisplayName,
            metadata: metadata,
            showsChineseKeys: showsChineseKeys,
            visibleMetadataKeys: visibleMetadataKeys
        )
        activityShareItem = ActivityShareItem(items: [text])
    }
}

#endif
