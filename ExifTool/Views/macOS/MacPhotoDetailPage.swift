#if os(macOS)

//
//  PhotoDetailPage.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct MacPhotoDetailPage: View {
    let asset: PhotoAsset
    let navigationTitle: String
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?
    let suppliedDetail: PhotoDetailState?

    @Binding private var showsChineseKeys: Bool
    @State private var detail = PhotoDetailState.loading
    @State private var metadataRequestID = UUID()
    @State private var previewImage: PlatformImage?
    @State private var previewRequestID = UUID()
    @State private var activityShareItem: ActivityShareItem?
    @State private var isPreparingPhotoShare = false
    @State private var shareErrorMessage: String?

    init(
        asset: PhotoAsset,
        showsChineseKeys: Binding<Bool>,
        navigationTitle: String,
        highlightedMetadataKeys: Set<String> = [],
        visibleMetadataKeys: Set<String>? = nil,
        suppliedDetail: PhotoDetailState? = nil
    ) {
        self.asset = asset
        self.navigationTitle = navigationTitle
        _showsChineseKeys = showsChineseKeys
        self.highlightedMetadataKeys = highlightedMetadataKeys
        self.visibleMetadataKeys = visibleMetadataKeys
        self.suppliedDetail = suppliedDetail
    }

    var body: some View {
        MacPhotoDetailStateContent(
            previewImage: previewImage,
            detail: displayedDetail,
            showsChineseKeys: showsChineseKeys,
            highlightedMetadataKeys: highlightedMetadataKeys,
            visibleMetadataKeys: visibleMetadataKeys
        )
            .task(id: asset.id) {
                guard suppliedDetail == nil else {
                    return
                }
                await loadMetadata()
            }
            .task(id: asset.id) {
                await loadPreview()
            }
            .alert("无法分享", isPresented: shareErrorBinding) {
                Button("好", role: .cancel) {
                    shareErrorMessage = nil
                }
            } message: {
                if let shareErrorMessage {
                    Text(shareErrorMessage)
                }
            }
            .photoDetailActivityShareSheet(item: $activityShareItem)
            .navigationTitle(navigationTitle)
            .platformInlineNavigationTitle()
            .toolbar {
                MacPhotoDetailPlatformToolbar(
                    showsChineseKeys: $showsChineseKeys,
                    isPreparingPhotoShare: isPreparingPhotoShare,
                    canShareParameters: loadedMetadata != nil,
                    onSharePhoto: sharePhoto,
                    onShareParameters: shareParameters
                )
            }
            .platformTabBarHidden()
    }

    private func loadMetadata() async {
        let requestID = UUID()
        metadataRequestID = requestID
        detail = .loading
        let newDetail = await PhotoLoader.metadata(for: asset, allowNetwork: false)
        guard !Task.isCancelled, requestID == metadataRequestID else {
            return
        }

        detail = newDetail
    }

    private func loadPreview() async {
        let requestID = UUID()
        previewRequestID = requestID
        previewImage = nil
        let newImage = await PhotoLoader.previewImage(
            for: asset,
            size: CGSize(width: 900, height: 900)
        )
        guard !Task.isCancelled, requestID == previewRequestID else {
            return
        }

        previewImage = newImage
    }

    private var loadedMetadata: PhotoMetadata? {
        guard case .loaded(let metadata) = displayedDetail else {
            return nil
        }

        return metadata
    }

    private var displayedDetail: PhotoDetailState {
        suppliedDetail ?? detail
    }

    private var shareErrorBinding: Binding<Bool> {
        Binding(
            get: { shareErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    shareErrorMessage = nil
                }
            }
        )
    }

    private func sharePhoto() {
        isPreparingPhotoShare = true

        Task {
            do {
                let url = try await PhotoLoader.shareablePhotoURL(for: asset, allowNetwork: false)
                activityShareItem = ActivityShareItem(items: [url])
            } catch {
                shareErrorMessage = photoShareErrorMessage(for: error)
            }

            isPreparingPhotoShare = false
        }
    }

    private func shareParameters() {
        guard let metadata = loadedMetadata else {
            shareErrorMessage = AppLocalization.string("photoDetail.shareParametersNotReady")
            return
        }

        let text = MetadataShareFormatter.text(
            for: asset,
            metadata: metadata,
            showsChineseKeys: showsChineseKeys,
            visibleMetadataKeys: visibleMetadataKeys
        )
        activityShareItem = ActivityShareItem(items: [text])
    }

    private func photoShareErrorMessage(for error: Error) -> String {
        return error.localizedDescription
    }

}

private struct MacPhotoDetailStateContent: View {
    let previewImage: PlatformImage?
    let detail: PhotoDetailState
    let showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?

    var body: some View {
        switch detail {
        case .loading:
            List {
                Section {
                    MacPhotoPreview(image: previewImage)
                }

                Section {
                    ProgressView("正在读取 Exif")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        case .loaded(let metadata):
            MacPhotoMetadataContent(
                previewImage: previewImage,
                metadata: metadata,
                showsChineseKeys: showsChineseKeys,
                highlightedMetadataKeys: highlightedMetadataKeys,
                visibleMetadataKeys: visibleMetadataKeys
            )
        case .failed(let message):
            MacPhotoDetailPlaceholderList(previewImage: previewImage) {
                ContentUnavailableView(
                    "无法读取 Exif",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
    }
}

private struct MacPhotoDetailPlaceholderList<Content: View>: View {
    let previewImage: PlatformImage?
    @ViewBuilder let content: Content

    var body: some View {
        List {
            Section {
                MacPhotoPreview(image: previewImage)
            }

            Section {
                content
            }
        }
    }
}

struct ActivityShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

private enum MetadataShareFormatter {
    static func text(
        for asset: PhotoAsset,
        metadata: PhotoMetadata,
        showsChineseKeys: Bool,
        visibleMetadataKeys: Set<String>?
    ) -> String {
        let projection = MetadataDisplayProjection(
            metadata: metadata,
            showsChineseKeys: showsChineseKeys,
            visibleMetadataKeys: visibleMetadataKeys
        )
        var lines = [AppLocalization.string("metadataShare.title")]

        if let displayName = asset.displayName {
            lines.append("\(AppLocalization.string("metadataShare.fileName")): \(displayName)")
        }
        lines.append("\(AppLocalization.string("metadataShare.dimensions")): \(asset.pixelWidth)x\(asset.pixelHeight)")
        if let creationDate = asset.creationDate {
            lines.append("\(AppLocalization.string("metadataShare.dateTaken")): \(creationDate.formatted(date: .numeric, time: .shortened))")
        }
        if let coordinate = metadata.coordinate {
            lines.append("\(AppLocalization.string("metadataShare.location")): \(LocationFormatter.coordinateText(coordinate))")
        }

        for section in projection.sections {
            lines.append("")
            lines.append("[\(section.title)]")
            if section.itemGroups.isEmpty {
                appendItems(section.items, to: &lines)
            } else {
                for group in section.itemGroups {
                    lines.append("")
                    lines.append(group.title)
                    appendItems(group.items, to: &lines)
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func appendItems(_ items: [MetadataDisplayItem], to lines: inout [String]) {
        for item in items {
            lines.append("\(item.title): \(item.value)")
        }
    }
}

#endif
