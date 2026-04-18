//
//  PhotoDetailPage.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import CoreLocation
import ImageIO
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct PhotoDetailPage: View {
    let asset: PhotoAsset
    let readOnlyMode: Bool
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?

    @Environment(\.openURL) private var openURL
    @AppStorage("allowsICloudDownload") private var allowsICloudDownload = false
    @Binding private var showsChineseKeys: Bool
    @State private var detail = PhotoDetailState.loading
    @State private var mapCoordinate: CLLocationCoordinate2D?
    @State private var isMapChooserPresented = false
    @State private var isDownloadingOriginal = false
    @State private var showsICloudDownloadExplanation = false
    @State private var activityShareItem: ActivityShareItem?
    @State private var isPreparingPhotoShare = false
    @State private var shareErrorMessage: String?
    @State private var selectedMetadataSectionID: String?

    init(
        asset: PhotoAsset,
        readOnlyMode: Bool,
        showsChineseKeys: Binding<Bool>,
        highlightedMetadataKeys: Set<String> = [],
        visibleMetadataKeys: Set<String>? = nil
    ) {
        self.asset = asset
        self.readOnlyMode = readOnlyMode
        _showsChineseKeys = showsChineseKeys
        self.highlightedMetadataKeys = highlightedMetadataKeys
        self.visibleMetadataKeys = visibleMetadataKeys
    }

    var body: some View {
        legacyDetailLayout
            .task(id: asset.id) {
                selectedMetadataSectionID = nil
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
            .alert("无法分享", isPresented: shareErrorBinding) {
                Button("好", role: .cancel) {
                    shareErrorMessage = nil
                }
            } message: {
                if let shareErrorMessage {
                    Text(shareErrorMessage)
                }
            }
            .platformActivityShareSheet(item: $activityShareItem)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    actionMenu
                }
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

    private var actionMenu: some View {
        Menu {
            Button {
                showsChineseKeys.toggle()
            } label: {
                Label(showsChineseKeys ? "显示英文字段名" : "显示中文字段名", systemImage: "character.book.closed")
            }

            Divider()

            Button {
                sharePhoto()
            } label: {
                Label(isPreparingPhotoShare ? "正在准备照片" : "分享照片", systemImage: "photo")
            }
            .disabled(isPreparingPhotoShare)

            Button {
                shareParameters()
            } label: {
                Label("分享参数", systemImage: "list.bullet.rectangle")
            }
            .disabled(loadedMetadata == nil)

            if let photosAppURL {
                Divider()

                Button {
                    openURL(photosAppURL)
                } label: {
                    Label("打开系统相册", systemImage: "photo.on.rectangle.angled")
                }
            }
        } label: {
            if isPreparingPhotoShare {
                ProgressView()
            } else {
                Image(systemName: "ellipsis")
            }
        }
        .accessibilityLabel("更多操作")
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
        if !allowsICloudDownload {
            return AppLocalization.string("photoDetail.shareNeedsDownload")
        }

        return error.localizedDescription
    }

    private func metadataContent(_ metadata: PhotoMetadata) -> some View {
        let filteredSections = filteredMetadataSections(from: metadata)
        let selectedSection = selectedMetadataSection(from: filteredSections)
        let sectionSelectionSignature = filteredSections.map(\.id).joined(separator: "|")

        return VStack(alignment: .leading, spacing: 18) {
            if !filteredSections.isEmpty {
                metadataSectionSegments(sections: filteredSections, selectedSectionID: selectedSection?.id)
            }

            if filteredSections.isEmpty {
                ContentUnavailableView("没有 Exif 信息", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let selectedSection {
                if let coordinate = metadata.coordinate, isGPSMetadataSection(selectedSection) {
                    locationButton(coordinate)
                }

                MetadataSectionView(
                    section: selectedSection,
                    showsChineseKeys: showsChineseKeys,
                    highlightedMetadataKeys: highlightedMetadataKeys
                )
            }
        }
        .onAppear {
            updateSelectedMetadataSection(for: filteredSections)
        }
        .onChange(of: sectionSelectionSignature) {
            updateSelectedMetadataSection(for: filteredSections)
        }
    }

    private func locationButton(_ coordinate: CLLocationCoordinate2D) -> some View {
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

    private func metadataSectionSegments(sections: [MetadataSection], selectedSectionID: String?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections) { section in
                    metadataSectionSegment(section, isSelected: section.id == selectedSectionID)
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityLabel("参数分类")
    }

    private func metadataSectionSegment(_ section: MetadataSection, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMetadataSectionID = section.id
            }
        } label: {
            Text(MetadataDisplayLocalizer.sectionTitle(section, showsChinese: showsChineseKeys))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    isSelected ? Color.accentColor : Color.platformSecondaryBackground,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func isGPSMetadataSection(_ section: MetadataSection) -> Bool {
        section.id.caseInsensitiveCompare(String(kCGImagePropertyGPSDictionary)) == .orderedSame ||
        section.title.caseInsensitiveCompare("GPS") == .orderedSame
    }

    private func selectedMetadataSection(from sections: [MetadataSection]) -> MetadataSection? {
        guard let selectedMetadataSectionID,
              let selectedSection = sections.first(where: { $0.id == selectedMetadataSectionID }) else {
            return sections.first
        }

        return selectedSection
    }

    private func updateSelectedMetadataSection(for sections: [MetadataSection]) {
        guard selectedMetadataSection(from: sections)?.id != selectedMetadataSectionID else {
            return
        }

        selectedMetadataSectionID = sections.first?.id
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

    private var photosAppURL: URL? {
        guard asset.photoLibraryAsset != nil else {
            return nil
        }

        #if os(iOS)
        return URL(string: "photos-redirect://")
        #else
        return nil
        #endif
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
            for item in section.items {
                let key = MetadataDisplayLocalizer.keyTitle(item.key, showsChinese: showsChineseKeys)
                lines.append("\(key): \(item.value)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func sections(from metadata: PhotoMetadata, visibleMetadataKeys: Set<String>?) -> [MetadataSection] {
        guard let visibleMetadataKeys else {
            return metadata.sections
        }

        return metadata.sections.compactMap { section in
            let items = section.items.filter { visibleMetadataKeys.contains($0.key) }
            guard !items.isEmpty else {
                return nil
            }

            return MetadataSection(id: section.id, title: section.title, items: items)
        }
    }
}

private extension View {
    @ViewBuilder
    func platformActivityShareSheet(item: Binding<ActivityShareItem?>) -> some View {
        #if os(iOS)
        sheet(item: item) { shareItem in
            ActivityView(activityItems: shareItem.items)
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
#endif
