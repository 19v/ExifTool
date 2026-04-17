//
//  PhotoDetailPage.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import CoreLocation
import SwiftUI

struct PhotoDetailPage: View {
    let asset: PhotoAsset
    let readOnlyMode: Bool
    let showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?

    @Environment(\.openURL) private var openURL
    @AppStorage("allowsICloudDownload") private var allowsICloudDownload = false
    @State private var detail = PhotoDetailState.loading
    @State private var mapCoordinate: CLLocationCoordinate2D?
    @State private var isMapChooserPresented = false
    @State private var isDownloadingOriginal = false
    @State private var showsICloudDownloadExplanation = false

    init(
        asset: PhotoAsset,
        readOnlyMode: Bool,
        showsChineseKeys: Bool,
        highlightedMetadataKeys: Set<String> = [],
        visibleMetadataKeys: Set<String>? = nil
    ) {
        self.asset = asset
        self.readOnlyMode = readOnlyMode
        self.showsChineseKeys = showsChineseKeys
        self.highlightedMetadataKeys = highlightedMetadataKeys
        self.visibleMetadataKeys = visibleMetadataKeys
    }

    var body: some View {
        legacyDetailLayout
            .task(id: asset.id) {
                await loadMetadata(allowNetwork: false)
            }
            .confirmationDialog("选择地图", isPresented: $isMapChooserPresented, titleVisibility: .visible) {
                if let mapCoordinate {
                    Button("系统地图") {
                        openURL(MapDestination.appleMaps.url(for: mapCoordinate))
                    }
                    Button("高德地图") {
                        openURL(MapDestination.amap.url(for: mapCoordinate))
                    }
                    Button("Google Maps") {
                        openURL(MapDestination.googleMaps.url(for: mapCoordinate))
                    }
                }
                Button("取消", role: .cancel) { }
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
    }

    private var legacyDetailLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PhotoPreview(asset: asset)

                readOnlyBanner

                switch detail {
                case .loading:
                    ProgressView("正在读取 Exif")
                        .frame(maxWidth: .infinity, minHeight: 120)
                case .loaded(let metadata):
                    metadataContent(metadata)
                case .needsDownload(let message):
                    downloadOriginalContent(message)
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
    }

    private var readOnlyBanner: some View {
        Label(readOnlyMode ? "只读模式已开启，不会修改照片或写入元数据" : "只读模式已关闭", systemImage: readOnlyMode ? "lock" : "lock.open")
            .font(.callout)
            .foregroundStyle(readOnlyMode ? .green : .orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private func downloadOriginalContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView(
                "原图未在本机",
                systemImage: "icloud.and.arrow.down",
                description: Text(message)
            )
            .frame(maxWidth: .infinity, minHeight: 170)

            Button {
                if allowsICloudDownload {
                    Task {
                        await loadMetadata(allowNetwork: true)
                    }
                } else {
                    showsICloudDownloadExplanation = true
                }
            } label: {
                if isDownloadingOriginal {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("下载此照片原图并读取 Exif", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDownloadingOriginal)

            Text("只会为当前照片联网下载原图缓存，不会修改照片或写入元数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    private func metadataContent(_ metadata: PhotoMetadata) -> some View {
        let filteredSections = filteredMetadataSections(from: metadata)

        return VStack(alignment: .leading, spacing: 18) {
            if let coordinate = metadata.coordinate {
                Button {
                    mapCoordinate = coordinate
                    isMapChooserPresented = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "map")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("地理位置")
                                .font(.headline)
                            Text(LocationFormatter.coordinateText(coordinate))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityHint("选择地图应用打开这个位置")
            }

            if filteredSections.isEmpty {
                ContentUnavailableView("没有 Exif 信息", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(filteredSections) { section in
                    MetadataSectionView(
                        section: section,
                        showsChineseKeys: showsChineseKeys,
                        highlightedMetadataKeys: highlightedMetadataKeys
                    )
                }
            }
        }
    }

    private func filteredMetadataSections(from metadata: PhotoMetadata) -> [MetadataSection] {
        let sections: [MetadataSection]

        if let visibleMetadataKeys {
            sections = metadata.sections.compactMap { section in
                let items = section.items.filter { visibleMetadataKeys.contains($0.key) }
                guard !items.isEmpty else {
                    return nil
                }

                return MetadataSection(id: section.id, title: section.title, items: items)
            }
        } else {
            sections = metadata.sections
        }

        return sections
            .enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = specialMetadataSectionPriority(for: lhs.element)
                let rhsPriority = specialMetadataSectionPriority(for: rhs.element)

                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func specialMetadataSectionPriority(for section: MetadataSection) -> Int {
        switch section.id {
        case "fujifilm-parameters", "nikon-parameters":
            return 0
        default:
            return 1
        }
    }
}
