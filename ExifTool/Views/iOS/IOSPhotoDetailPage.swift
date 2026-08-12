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
    @State private var model = IOSPhotoDetailModel()

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
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PhotoPreview(asset: asset)
                ReadOnlyStatusBanner(isReadOnly: readOnlyMode)
                IOSPhotoDetailStateContent(
                    detail: model.detail,
                    isDownloadingOriginal: model.isDownloadingOriginal,
                    showsChineseKeys: showsChineseKeys,
                    highlightedMetadataKeys: highlightedMetadataKeys,
                    visibleMetadataKeys: visibleMetadataKeys,
                    onDownload: requestOriginalDownload
                )
            }
            .padding()
        }
            .task(id: asset.id) {
                await model.loadMetadata(for: asset, allowNetwork: false)
            }
            .alert("需要联网下载 iCloud 原图", isPresented: $model.showsICloudDownloadExplanation) {
                Button("保持离线", role: .cancel) { }
                Button("允许并下载") {
                    allowsICloudDownload = true
                    Task {
                        await model.loadMetadata(for: asset, allowNetwork: true)
                    }
                }
            } message: {
                Text("这张照片的原图可能只保存在 iCloud。应用需要联网把原图下载到本机后才能读取完整 Exif，你也可以保持离线，或在设置里改成仅显示已下载到本地的照片。")
            }
            .alert("无法分享", isPresented: $model.isShareErrorPresented) {
                Button("好", role: .cancel) {
                    model.shareErrorMessage = nil
                }
            } message: {
                if let shareErrorMessage = model.shareErrorMessage {
                    Text(shareErrorMessage)
                }
            }
            .photoDetailActivityShareSheet(item: $model.activityShareItem)
            .navigationTitle(navigationTitle)
            .platformInlineNavigationTitle()
            .toolbar {
                PhotoDetailPlatformToolbar(
                    showsChineseKeys: $showsChineseKeys,
                    photoNavigation: photoNavigation,
                    isPreparingPhotoShare: model.isPreparingPhotoShare,
                    canShareParameters: model.loadedMetadata != nil,
                    onSharePhoto: sharePhoto,
                    onShareParameters: shareParameters
                )
            }
            .platformTabBarHidden()
    }

    private func requestOriginalDownload() {
        if allowsICloudDownload {
            Task {
                await model.loadMetadata(for: asset, allowNetwork: true)
            }
        } else {
            model.showsICloudDownloadExplanation = true
        }
    }

    private func sharePhoto() {
        Task {
            await model.sharePhoto(asset: asset, allowsICloudDownload: allowsICloudDownload)
        }
    }

    private func shareParameters() {
        model.shareParameters(
            asset: asset,
            showsChineseKeys: showsChineseKeys,
            visibleMetadataKeys: visibleMetadataKeys
        )
    }

}

private struct IOSPhotoDetailStateContent: View {
    let detail: PhotoDetailState
    let isDownloadingOriginal: Bool
    let showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?
    let onDownload: () -> Void

    var body: some View {
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
                onDownload: onDownload
            )
        case .failed(let message):
            ContentUnavailableView(
                "无法读取 Exif",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
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

enum MetadataShareFormatter {
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
