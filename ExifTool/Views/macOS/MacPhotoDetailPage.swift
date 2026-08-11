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
    let readOnlyMode: Bool
    let navigationTitle: String
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?
    let suppliedDetail: PhotoDetailState?

    @Binding private var showsChineseKeys: Bool
    @State private var detail = PhotoDetailState.loading
    @State private var activityShareItem: ActivityShareItem?
    @State private var isPreparingPhotoShare = false
    @State private var shareErrorMessage: String?

    init(
        asset: PhotoAsset,
        readOnlyMode: Bool,
        showsChineseKeys: Binding<Bool>,
        navigationTitle: String,
        highlightedMetadataKeys: Set<String> = [],
        visibleMetadataKeys: Set<String>? = nil,
        suppliedDetail: PhotoDetailState? = nil
    ) {
        self.asset = asset
        self.readOnlyMode = readOnlyMode
        self.navigationTitle = navigationTitle
        _showsChineseKeys = showsChineseKeys
        self.highlightedMetadataKeys = highlightedMetadataKeys
        self.visibleMetadataKeys = visibleMetadataKeys
        self.suppliedDetail = suppliedDetail
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MacPhotoPreview(asset: asset)
                ReadOnlyStatusBanner(isReadOnly: readOnlyMode)

                switch displayedDetail {
                case .loading:
                    ProgressView("正在读取 Exif")
                        .frame(maxWidth: .infinity, minHeight: 120)
                case .loaded(let metadata):
                    MacPhotoMetadataContent(
                        metadata: metadata,
                        showsChineseKeys: showsChineseKeys,
                        highlightedMetadataKeys: highlightedMetadataKeys,
                        visibleMetadataKeys: visibleMetadataKeys
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
                guard suppliedDetail == nil else {
                    return
                }
                await loadMetadata()
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
        detail = .loading
        detail = await PhotoLoader.metadata(for: asset, allowNetwork: false)
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
