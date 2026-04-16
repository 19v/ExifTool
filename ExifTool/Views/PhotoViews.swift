//
//  PhotoViews.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import CoreLocation
import Photos
import SwiftUI
#if os(iOS)
import UIKit
internal import PhotosUI
#endif

struct PhotoPickerTabView: View {
    @ObservedObject var library: PhotoLibraryViewModel
    #if os(iOS)
    @ObservedObject var manualPicker: ManualPhotoPickerViewModel
    #endif
    let readOnlyMode: Bool
    
    var body: some View {
        NavigationStack {
            Group {
                #if os(iOS)
                switch library.authorizationState {
                case .denied:
                    ManualPhotoPickerAccessView(picker: manualPicker, readOnlyMode: readOnlyMode)
                default:
                    LibraryAuthorizationContent(library: library, emptyTitle: "没有可显示的照片") {
                        PhotoAssetGridView(
                            assets: library.assets,
                            readOnlyMode: readOnlyMode,
                            onRefresh: library.refresh
                        )
                    }
                }
                #else
                LibraryAuthorizationContent(library: library, emptyTitle: "没有可显示的照片") {
                    PhotoAssetGridView(
                        assets: library.assets,
                        readOnlyMode: readOnlyMode,
                        onRefresh: library.refresh
                    )
                }
                #endif
            }
            .navigationTitle("照片")
            .platformInlineNavigationTitle()
        }
    }
}

struct AlbumsTabView: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let readOnlyMode: Bool
    
    var body: some View {
        NavigationStack {
            LibraryAuthorizationContent(library: library, emptyTitle: "没有找到相册") {
                PlatformAlbumList(
                    albums: library.albums,
                    readOnlyMode: readOnlyMode,
                    onRefresh: library.refresh
                )
            }
            .navigationTitle("相册")
            .platformInlineNavigationTitle()
        }
    }
}

struct AlbumRowView: View {
    let album: PhotoAlbum
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.body)
                Text("\(album.assetCount) 张照片")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AlbumDetailView: View {
    let album: PhotoAlbum
    let readOnlyMode: Bool
    
    @State private var assets: [PhotoAsset] = []
    
    var body: some View {
        PhotoAssetGridView(assets: assets, readOnlyMode: readOnlyMode)
            .navigationTitle(album.title)
            .platformInlineNavigationTitle()
            .task(id: album.id) {
                assets = PhotoLibraryViewModel.fetchImageAssets(in: album.collection)
            }
    }
}

struct SearchTabView: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let readOnlyMode: Bool
    
    @State private var query = ""
    
    private var results: [PhotoAsset] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }
        
        return library.assets.filter { asset in
            PhotoSearchIndex.text(for: asset).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    
    var body: some View {
        NavigationStack {
            LibraryAuthorizationContent(library: library, emptyTitle: "没有可搜索的照片") {
                Group {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("搜索照片", systemImage: "magnifyingglass", description: Text("可以搜索日期、尺寸或照片标识符。"))
                    } else if results.isEmpty {
                        ContentUnavailableView("没有匹配照片", systemImage: "photo.on.rectangle.angled")
                    } else {
                        PhotoAssetGridView(
                            assets: results,
                            readOnlyMode: readOnlyMode,
                            onRefresh: library.refresh
                        )
                    }
                }
            }
            .navigationTitle("搜索")
            .platformInlineNavigationTitle()
            .searchable(text: $query, prompt: "搜索照片")
        }
    }
}

struct SettingsTabView: View {
    @Binding var readOnlyMode: Bool
    #if os(iOS)
    let authorizationState: PhotoLibraryViewModel.AuthorizationState
    @Environment(\.openURL) private var openURL
    #else
    init(readOnlyMode: Binding<Bool>) {
        self._readOnlyMode = readOnlyMode
    }
    #endif
    
    #if os(iOS)
    init(
        readOnlyMode: Binding<Bool>,
        authorizationState: PhotoLibraryViewModel.AuthorizationState
    ) {
        self._readOnlyMode = readOnlyMode
        self.authorizationState = authorizationState
    }
    #endif
    
    var body: some View {
        NavigationStack {
            Form {
                Section("安全") {
                    Toggle("只读模式", isOn: $readOnlyMode)
                    Text("开启后，应用只读取照片和 Exif，不会修改照片或写入元数据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                #if os(iOS)
                if showsSettingsShortcut {
                    Section("相册权限") {
                        Button(photoPermissionActionTitle) {
                            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            
                            openURL(settingsURL)
                        }
                        
                        Text(photoPermissionDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif
                
                Section("应用") {
                    LabeledContent("名称", value: "ExifTool")
                    PlatformSettingsImportSource()
                }
            }
            .navigationTitle("设置")
            .platformInlineNavigationTitle()
        }
    }
    
    #if os(iOS)
    private var showsSettingsShortcut: Bool {
        authorizationState != .unknown
    }
    
    private var photoPermissionActionTitle: String {
        switch authorizationState {
        case .authorized:
            return "前往系统设置管理全部图库权限"
        case .limited:
            return "前往系统设置管理部分图片权限"
        case .denied:
            return "前往系统设置重新开启相册权限"
        case .empty:
            return "前往系统设置检查相册权限"
        case .unknown:
            return "前往系统设置"
        }
    }
    
    private var photoPermissionDescription: String {
        switch authorizationState {
        case .authorized:
            return "当前已允许访问整个图库。如果想改成部分图片，或直接关闭权限，可以前往系统设置调整。"
        case .limited:
            return "当前只允许访问部分图片。如果想扩大到整个图库、重新挑选照片，或直接关闭权限，可以前往系统设置调整。"
        case .denied:
            return "当前未允许访问系统照片库。如果想重新开启权限，可以前往系统设置调整。"
        case .empty:
            return "当前权限下没有可用照片。如果想检查是否改成了部分图片权限，或直接关闭权限，可以前往系统设置调整。"
        case .unknown:
            return "可以前往系统设置查看当前的相册权限。"
        }
    }
    #endif
}

struct LibraryAuthorizationContent<Content: View>: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let emptyTitle: String
    @ViewBuilder let content: Content
    
    var body: some View {
        Group {
            switch library.authorizationState {
            case .unknown:
                ProgressView("正在读取照片")
            case .denied:
                ContentUnavailableView(
                    "无法访问照片",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("请在系统设置中允许读取照片。应用只读取照片，不会修改照片。")
                )
            case .limited, .authorized:
                content
            case .empty:
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "photo",
                    description: Text("当前权限范围内没有照片。")
                )
            }
        }
    }
}

struct PhotoAssetGridView: View {
    let assets: [PhotoAsset]
    let readOnlyMode: Bool
    let onRefresh: (() async -> Void)?
    
    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]
    
    init(assets: [PhotoAsset], readOnlyMode: Bool, onRefresh: (() async -> Void)? = nil) {
        self.assets = assets
        self.readOnlyMode = readOnlyMode
        self.onRefresh = onRefresh
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(assets) { asset in
                    NavigationLink {
                        PhotoDetailView(
                            assets: assets,
                            initialAssetID: asset.id,
                            readOnlyMode: readOnlyMode
                        )
                    } label: {
                        PhotoThumbnail(asset: asset)
                    }
                    .buttonStyle(.plain)
                    .id(asset.id)
                }
            }
            .padding(3)
        }
        .refreshable {
            await onRefresh?()
        }
        .overlay(alignment: .bottom) {
            if readOnlyMode {
                Text("只读模式已开启")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 12)
            }
        }
    }
}

struct PhotoThumbnail: View {
    let asset: PhotoAsset
    
    @Environment(\.displayScale) private var displayScale
    @State private var image: PlatformImage?
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(Color.platformSecondaryBackground)
                
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.width)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.width)
            .clipShape(Rectangle())
            .clipped()
            .task(id: thumbnailTaskID(width: proxy.size.width)) {
                guard proxy.size.width > 1 else {
                    return
                }
                
                let pixelLength = max(360, ceil(proxy.size.width * displayScale))
                image = await PhotoLoader.thumbnail(for: asset, size: CGSize(width: pixelLength, height: pixelLength))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("照片")
    }
    
    private func thumbnailTaskID(width: CGFloat) -> String {
        "\(asset.id)-\(Int(ceil(width * displayScale)))"
    }
}

struct PhotoDetailView: View {
    let assets: [PhotoAsset]
    let initialAssetID: String
    let readOnlyMode: Bool
    
    @State private var showsChineseKeys = false
    @State private var selectedAssetID: String
    
    init(assets: [PhotoAsset], initialAssetID: String, readOnlyMode: Bool) {
        self.assets = assets
        self.initialAssetID = initialAssetID
        self.readOnlyMode = readOnlyMode
        _selectedAssetID = State(initialValue: initialAssetID)
    }
    
    var body: some View {
        Group {
            if assets.isEmpty {
                ContentUnavailableView("没有可显示的照片", systemImage: "photo")
            } else {
                TabView(selection: $selectedAssetID) {
                    ForEach(assets) { asset in
                        PhotoDetailPage(
                            asset: asset,
                            readOnlyMode: readOnlyMode,
                            showsChineseKeys: showsChineseKeys
                        )
                        .tag(asset.id)
                    }
                }
                .platformDetailPagingStyle()
            }
        }
        .navigationTitle(navigationTitle)
        .platformInlineNavigationTitle()
        .platformTabBarHidden()
        .toolbar {
            ToolbarItem(placement: .platformLanguageToggle) {
                Button(showsChineseKeys ? "EN" : "中文") {
                    showsChineseKeys.toggle()
                }
                .accessibilityLabel(showsChineseKeys ? "切换为英文字段名" : "切换为中文字段名")
            }
        }
    }
    
    private var navigationTitle: String {
        guard let currentIndex = assets.firstIndex(where: { $0.id == selectedAssetID }) else {
            return "照片信息"
        }
        
        return "照片信息 \(currentIndex + 1)/\(assets.count)"
    }
}

struct PhotoDetailPage: View {
    let asset: PhotoAsset
    let readOnlyMode: Bool
    let showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?
    
    @Environment(\.openURL) private var openURL
    @State private var detail = PhotoDetailState.loading
    @State private var mapCoordinate: CLLocationCoordinate2D?
    @State private var isMapChooserPresented = false
    @State private var isDownloadingOriginal = false
    
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
                Task {
                    await loadMetadata(allowNetwork: true)
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

struct PhotoPreview: View {
    let asset: PhotoAsset
    
    @State private var image: PlatformImage?
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.platformSecondaryBackground)
            
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: asset.id) {
            image = await PhotoLoader.thumbnail(for: asset, size: CGSize(width: 900, height: 900))
        }
    }
}

struct MetadataSectionView: View {
    let section: MetadataSection
    let showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline)
            
            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        MetadataKeyLabel(englishKey: item.key, showsChinese: showsChineseKeys)
                        Text(item.value)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(highlightedMetadataKeys.contains(item.key) ? Color.accentColor.opacity(0.12) : Color.clear)
                    
                    if item.id != section.items.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct MetadataKeyLabel: View {
    let englishKey: String
    let showsChinese: Bool
    
    var body: some View {
        Text(displayKey)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .frame(width: 120, alignment: .leading)
            .accessibilityLabel(displayKey)
    }
    
    private var displayKey: String {
        if showsChinese, let chineseKey = MetadataKeyTranslator.chineseName(for: englishKey) {
            return chineseKey
        }
        
        return englishKey
    }
}
