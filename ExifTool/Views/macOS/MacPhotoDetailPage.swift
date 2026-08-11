#if os(macOS)

//
//  PhotoDetailPage.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import CoreLocation
import ImageIO
import SwiftUI

struct MacPhotoDetailPage: View {
    let asset: PhotoAsset
    let readOnlyMode: Bool
    let navigationTitle: String
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?
    let suppliedDetail: PhotoDetailState?

    @Environment(\.openURL) private var openURL
    @Binding private var showsChineseKeys: Bool
    @State private var detail = PhotoDetailState.loading
    @State private var mapCoordinate: CLLocationCoordinate2D?
    @State private var isMapChooserPresented = false
    @State private var activityShareItem: ActivityShareItem?
    @State private var isPreparingPhotoShare = false
    @State private var shareErrorMessage: String?
    @State private var selectedMetadataSectionID: String?

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
        legacyDetailLayout
            .task(id: asset.id) {
                selectedMetadataSectionID = nil
                guard suppliedDetail == nil else {
                    return
                }
                await loadMetadata()
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

    private var legacyDetailLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MacPhotoPreview(asset: asset)

                readOnlyBanner

                switch displayedDetail {
                case .loading:
                    ProgressView("正在读取 Exif")
                        .frame(maxWidth: .infinity, minHeight: 120)
                case .loaded(let metadata):
                    metadataContent(metadata)
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

                MacMetadataSectionView(
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
            sections = metadata.sections.compactMap { section -> MetadataSection? in
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
