#if os(iOS)

//
//  PhotoDetailPage.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct PhotoDetailPage: View {
    let asset: PhotoAsset
    let readOnlyMode: Bool
    let navigationTitle: String
    let photoNavigation: PhotoNavigationConfiguration?
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?

    @AppStorage("allowsICloudDownload") private var allowsICloudDownload = false
    @Binding private var showsChineseKeys: Bool
    @State private var detail = PhotoDetailState.loading
    @State private var isDownloadingOriginal = false
    @State private var showsICloudDownloadExplanation = false
    @State private var activityShareItem: ActivityShareItem?
    @State private var isPreparingPhotoShare = false
    @State private var shareErrorMessage: String?

    init(
        asset: PhotoAsset,
        readOnlyMode: Bool,
        showsChineseKeys: Binding<Bool>,
        navigationTitle: String,
        photoNavigation: PhotoNavigationConfiguration? = nil,
        highlightedMetadataKeys: Set<String> = [],
        visibleMetadataKeys: Set<String>? = nil
    ) {
        self.asset = asset
        self.readOnlyMode = readOnlyMode
        self.navigationTitle = navigationTitle
        self.photoNavigation = photoNavigation
        _showsChineseKeys = showsChineseKeys
        self.highlightedMetadataKeys = highlightedMetadataKeys
        self.visibleMetadataKeys = visibleMetadataKeys
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PhotoPreview(asset: asset)
                ReadOnlyStatusBanner(isReadOnly: readOnlyMode)

                switch detail {
                case .loading:
                    ProgressView("正在读取 Exif")
                        .frame(maxWidth: .infinity, minHeight: 120)
                case .loaded(let metadata):
                    IOSPhotoMetadataContent(
                        metadata: metadata,
                        showsChineseKeys: showsChineseKeys,
                        highlightedMetadataKeys: highlightedMetadataKeys,
                        visibleMetadataKeys: visibleMetadataKeys
                    )
                case .needsDownload(let message):
                    IOSPhotoDownloadPrompt(
                        message: message,
                        isDownloading: isDownloadingOriginal,
                        onDownload: requestOriginalDownload
                    )
                case .failed(let message):
                    ContentUnavailableView(
                        "无法读取 Exif",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            }
            .padding()
        }
            .task(id: asset.id) {
                await loadMetadata(allowNetwork: false)
            }
            .alert("需要联网下载 iCloud 原图", isPresented: $showsICloudDownloadExplanation) {
                Button("保持离线", role: .cancel) { }
                Button("允许并下载") {
                    allowsICloudDownload = true
                    Task {
                        await loadMetadata(allowNetwork: true)
                    }
                }
            } message: {
                Text("这张照片的原图可能只保存在 iCloud。应用需要联网把原图下载到本机后才能读取完整 Exif，你也可以保持离线，或在设置里改成仅显示已下载到本地的照片。")
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
                PhotoDetailPlatformToolbar(
                    showsChineseKeys: $showsChineseKeys,
                    photoNavigation: photoNavigation,
                    isPreparingPhotoShare: isPreparingPhotoShare,
                    canShareParameters: loadedMetadata != nil,
                    onSharePhoto: sharePhoto,
                    onShareParameters: shareParameters
                )
            }
            .platformTabBarHidden()
    }

    private func requestOriginalDownload() {
        if allowsICloudDownload {
            Task {
                await loadMetadata(allowNetwork: true)
            }
        } else {
            showsICloudDownloadExplanation = true
        }
    }

    private func loadMetadata(allowNetwork: Bool) async {
        if allowNetwork {
            isDownloadingOriginal = true
        } else {
            detail = .loading
        }

        let newDetail = await PhotoLoader.metadata(for: asset, allowNetwork: allowNetwork)
        detail = newDetail
        isDownloadingOriginal = false
    }

    private var loadedMetadata: PhotoMetadata? {
        guard case .loaded(let metadata) = detail else {
            return nil
        }

        return metadata
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
                let url = try await PhotoLoader.shareablePhotoURL(for: asset, allowNetwork: allowsICloudDownload)
                activityShareItem = ActivityShareItem(
                    items: [url],
                    cleanupURL: PhotoTemporaryFileStore.isShareFile(url) ? url : nil
                )
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
        if !allowsICloudDownload {
            return AppLocalization.string("photoDetail.shareNeedsDownload")
        }

        return error.localizedDescription
    }

}

private struct IOSPhotoDownloadPrompt: View {
    let message: String
    let isDownloading: Bool
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView(
                "原图未在本机",
                systemImage: "icloud.and.arrow.down",
                description: Text(message)
            )
            .frame(maxWidth: .infinity, minHeight: 170)

            Button(action: onDownload) {
                if isDownloading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("下载此照片原图并读取 Exif", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDownloading)

            Text("只会为当前照片联网下载原图缓存，不会修改照片或写入元数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct PhotoNavigationConfiguration {
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let selectPrevious: () -> Void
    let selectNext: () -> Void
}

struct ActivityShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
    let cleanupURL: URL?

    init(items: [Any], cleanupURL: URL? = nil) {
        self.items = items
        self.cleanupURL = cleanupURL
    }
}

private enum MetadataShareFormatter {
    static func text(
        for asset: PhotoAsset,
        metadata: PhotoMetadata,
        showsChineseKeys: Bool,
        visibleMetadataKeys: Set<String>?
    ) -> String {
        let sections = sections(from: metadata, visibleMetadataKeys: visibleMetadataKeys)
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

        for section in sections {
            lines.append("")
            lines.append("[\(MetadataDisplayLocalizer.sectionTitle(section, showsChinese: showsChineseKeys))]")
            if section.itemGroups.isEmpty {
                appendItems(section.items, to: &lines, showsChineseKeys: showsChineseKeys)
            } else {
                for group in section.itemGroups {
                    lines.append("")
                    lines.append(MetadataDisplayLocalizer.sectionTitle(
                        MetadataSection(id: group.id, title: group.title, items: group.items),
                        showsChinese: showsChineseKeys
                    ))
                    appendItems(group.items, to: &lines, showsChineseKeys: showsChineseKeys)
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func appendItems(_ items: [MetadataItem], to lines: inout [String], showsChineseKeys: Bool) {
        for item in items {
            let key = MetadataDisplayLocalizer.keyTitle(item.key, showsChinese: showsChineseKeys)
            let value = MetadataDisplayLocalizer.valueText(item.value, showsChinese: showsChineseKeys)
            lines.append("\(key): \(value)")
        }
    }

    private static func sections(from metadata: PhotoMetadata, visibleMetadataKeys: Set<String>?) -> [MetadataSection] {
        guard let visibleMetadataKeys else {
            return metadata.sections
        }

        return metadata.sections.compactMap { section -> MetadataSection? in
            let items = section.items.filter { visibleMetadataKeys.contains($0.key) }
            let itemGroups = section.itemGroups.compactMap { group -> MetadataItemGroup? in
                let groupItems = group.items.filter { visibleMetadataKeys.contains($0.key) }
                guard !groupItems.isEmpty else {
                    return nil
                }

                return MetadataItemGroup(id: group.id, title: group.title, items: groupItems)
            }

            guard !items.isEmpty || !itemGroups.isEmpty else {
                return nil
            }

            return MetadataSection(id: section.id, title: section.title, items: items, itemGroups: itemGroups)
        }
    }
}

#endif
