//
//  PhotoViews.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Combine
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
                            isLoadingMore: library.showsOnlyLocalAssets && library.hasMoreLocalAssets,
                            onAssetAppear: library.loadMoreLocalAssetsIfNeeded,
                            onRefresh: library.refresh
                        )
                    }
                }
                #else
                LibraryAuthorizationContent(library: library, emptyTitle: "没有可显示的照片") {
                    PhotoAssetGridView(
                        assets: library.assets,
                        readOnlyMode: readOnlyMode,
                        isLoadingMore: false,
                        onRefresh: library.refresh
                    )
                }
                #endif
            }
            .navigationTitle("照片")
            .platformInlineNavigationTitle()
            .safeAreaInset(edge: .bottom) {
                if library.showsOnlyLocalAssets, let bannerText = localPhotosBanner {
                    LocalPhotosStatusBanner(
                        text: bannerText,
                        state: localPhotosBannerState,
                        localPhotosCount: library.localPhotosCount,
                        localAlbumsCount: nil,
                        emphasis: .floating
                    )
                }
            }
        }
    }

    private var localPhotosBanner: String? {
        if library.isFilteringLocalAssets && library.assets.isEmpty {
            return "正在读取已下载到本地的照片"
        }
        if library.hasMoreLocalAssets {
            return "当前仅显示已探测到的本地照片，继续下滑会加载更多"
        }
        if library.isBuildingLocalAlbumStats {
            return "照片已加载完成，后台仍在补充相册统计"
        }
        return nil
    }

    private var localPhotosBannerState: PhotoLibraryViewModel.LocalPhotosSummaryState? {
        if library.isFilteringLocalAssets && library.assets.isEmpty {
            return .loading
        }
        if library.hasMoreLocalAssets {
            return .paginating
        }
        if library.isBuildingLocalAlbumStats {
            return .buildingAlbums
        }
        return nil
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
                    showsOnlyLocalAssets: library.showsOnlyLocalAssets,
                    onRefresh: library.refresh
                )
            }
            .navigationTitle("相册")
            .platformInlineNavigationTitle()
            .task(id: library.showsOnlyLocalAssets) {
                if library.showsOnlyLocalAssets {
                    library.buildRemainingLocalAlbumStatsIfNeeded()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if library.showsOnlyLocalAssets && library.isBuildingLocalAlbumStats {
                    localAlbumStatsBanner
                }
            }
        }
    }

    private var localAlbumStatsBanner: some View {
        LocalPhotosStatusBanner(
            text: "正在补充剩余本地照片的相册统计",
            state: .buildingAlbums,
            localPhotosCount: library.localPhotosCount,
            localAlbumsCount: library.localAlbumsCount,
            emphasis: .floating
        )
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
    let showsOnlyLocalAssets: Bool
    
    @StateObject private var pager = LocalAssetPagingViewModel()
    @State private var allAssets: [PhotoAsset] = []
    
    var body: some View {
        PhotoAssetGridView(
            assets: displayedAssets,
            readOnlyMode: readOnlyMode,
            isLoadingMore: showsOnlyLocalAssets ? pager.hasMoreAssets : false,
            onAssetAppear: assetAppearHandler
        )
            .navigationTitle(album.title)
            .platformInlineNavigationTitle()
            .task(id: album.id) {
                let fetchedAssets = await PhotoLibraryViewModel.fetchImageAssetsOffMain(in: album.collection)
                allAssets = fetchedAssets
                if showsOnlyLocalAssets {
                    pager.setSourceAssets(fetchedAssets)
                } else {
                    pager.reset()
                }
            }
    }

    private var displayedAssets: [PhotoAsset] {
        showsOnlyLocalAssets ? pager.assets : allAssets
    }

    private var assetAppearHandler: ((String?) -> Void)? {
        showsOnlyLocalAssets ? { pager.loadMoreIfNeeded(currentAssetID: $0) } : nil
    }
}

struct SearchTabView: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let readOnlyMode: Bool
    
    @State private var query = ""
    @StateObject private var pager = LocalAssetPagingViewModel()
    
    private var results: [PhotoAsset] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }
        
        return library.searchableAssets.filter { asset in
            PhotoSearchIndex.text(for: asset).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    
    var body: some View {
        NavigationStack {
            LibraryAuthorizationContent(library: library, emptyTitle: "没有可搜索的照片") {
                searchContent
            }
            .navigationTitle("搜索")
            .platformInlineNavigationTitle()
            .searchable(text: $query, prompt: "搜索照片")
            .onChange(of: query) { _, _ in
                refreshSearchPager()
            }
            .onChange(of: library.showsOnlyLocalAssets) { _, _ in
                refreshSearchPager()
            }
            .onChange(of: library.searchableAssets.map(\.id)) { _, _ in
                refreshSearchPager()
            }
            .task {
                refreshSearchPager()
            }
            .safeAreaInset(edge: .bottom) {
                if library.showsOnlyLocalAssets, let bannerText = searchBannerText {
                    LocalPhotosStatusBanner(
                        text: bannerText,
                        state: searchBannerState,
                        localPhotosCount: searchBannerPhotosCount,
                        localAlbumsCount: searchBannerAlbumsCount,
                        emphasis: .floating
                    )
                }
            }
        }
    }

    private var displayedSearchAssets: [PhotoAsset] {
        library.showsOnlyLocalAssets ? pager.assets : results
    }

    private var showsSearchLoading: Bool {
        library.showsOnlyLocalAssets && pager.hasMoreAssets
    }

    @ViewBuilder
    private var searchContent: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("搜索照片", systemImage: "magnifyingglass", description: Text("可以搜索日期、尺寸或照片标识符。"))
        } else if displayedSearchAssets.isEmpty && !showsSearchLoading {
            ContentUnavailableView("没有匹配照片", systemImage: "photo.on.rectangle.angled")
        } else {
            PhotoAssetGridView(
                assets: displayedSearchAssets,
                readOnlyMode: readOnlyMode,
                isLoadingMore: showsSearchLoading,
                onAssetAppear: searchAssetAppearHandler,
                onRefresh: library.refresh
            )
        }
    }

    private var searchAssetAppearHandler: ((String?) -> Void)? {
        library.showsOnlyLocalAssets ? { pager.loadMoreIfNeeded(currentAssetID: $0) } : nil
    }

    private func refreshSearchPager() {
        if library.showsOnlyLocalAssets {
            pager.setSourceAssets(results)
        } else {
            pager.reset()
        }
    }

    private var searchBannerText: String? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if displayedSearchAssets.isEmpty && showsSearchLoading {
            return "正在筛选符合搜索条件的本地照片"
        }
        if showsSearchLoading {
            return "当前搜索结果还在补充，继续下滑会加载更多本地照片"
        }
        if library.isBuildingLocalAlbumStats {
            return "搜索结果已加载完成，后台仍在补充相册统计"
        }
        return nil
    }

    private var searchBannerState: PhotoLibraryViewModel.LocalPhotosSummaryState? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if displayedSearchAssets.isEmpty && showsSearchLoading {
            return .loading
        }
        if showsSearchLoading {
            return .paginating
        }
        if library.isBuildingLocalAlbumStats {
            return .buildingAlbums
        }
        return nil
    }

    private var searchBannerPhotosCount: Int? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return displayedSearchAssets.count
    }

    private var searchBannerAlbumsCount: Int? {
        library.isBuildingLocalAlbumStats ? library.localAlbumsCount : nil
    }
}

struct LocalPhotosStatusBanner: View {
    enum Emphasis {
        case compact
        case card
        case floating
    }

    let text: String
    let state: PhotoLibraryViewModel.LocalPhotosSummaryState?
    let localPhotosCount: Int?
    let localAlbumsCount: Int?
    let emphasis: Emphasis

    var body: some View {
        HStack(spacing: 12) {
            statusPulse

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let localPhotosCount {
                        countChip(title: "本地", value: localPhotosCount)
                    }

                    if showsAlbumCount, let localAlbumsCount {
                        countChip(title: "相册", value: localAlbumsCount)
                    }
                }

                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if emphasis == .floating {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
        .shadow(
            color: emphasis == .floating ? .black.opacity(0.12) : .clear,
            radius: emphasis == .floating ? 16 : 0,
            y: emphasis == .floating ? 8 : 0
        )
        .padding(.horizontal, horizontalInset)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: localPhotosCount)
        .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: localAlbumsCount)
        .animation(.easeInOut(duration: 0.2), value: text)
    }

    private var showsAlbumCount: Bool {
        switch state {
        case .buildingAlbums, .complete:
            return true
        case .loading, .paginating, .none:
            return localAlbumsCount != nil && localAlbumsCount != 0
        }
    }

    private var statusPulse: some View {
        Circle()
            .fill(statusColor.gradient)
            .frame(width: 10, height: 10)
            .overlay {
                Circle()
                    .stroke(statusColor.opacity(0.22), lineWidth: 8)
                    .scaleEffect(needsPulse ? 1.16 : 1)
                    .opacity(needsPulse ? 1 : 0.35)
            }
            .animation(
                needsPulse ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .easeOut(duration: 0.2),
                value: needsPulse
            )
    }

    @ViewBuilder
    private func countChip(title: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatted(value))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch state {
        case .complete:
            return .green
        case .loading, .paginating, .buildingAlbums, .none:
            return .orange
        }
    }

    private var needsPulse: Bool {
        switch state {
        case .complete:
            return false
        case .loading, .paginating, .buildingAlbums, .none:
            return true
        }
    }

    private var backgroundStyle: some ShapeStyle {
        switch emphasis {
        case .compact:
            return AnyShapeStyle(Color.platformSecondaryBackground)
        case .card:
            return AnyShapeStyle(Color.platformSecondaryBackground)
        case .floating:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var horizontalInset: CGFloat {
        switch emphasis {
        case .compact, .card:
            return 12
        case .floating:
            return 16
        }
    }

    private var topInset: CGFloat {
        switch emphasis {
        case .compact:
            return 8
        case .card:
            return 0
        case .floating:
            return 8
        }
    }

    private var bottomInset: CGFloat {
        switch emphasis {
        case .compact:
            return 6
        case .card:
            return 0
        case .floating:
            return 6
        }
    }

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

@MainActor
final class LocalAssetPagingViewModel: ObservableObject {
    private static let scanBatchSize = 48
    private static let pageSize = 90
    private static let prefetchThreshold = 24

    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var hasMoreAssets = false

    private var sourceAssets: [PhotoAsset] = []
    private var nextScanIndex = 0
    private var isLoading = false
    private var sessionID = UUID()

    func setSourceAssets(_ assets: [PhotoAsset]) {
        sessionID = UUID()
        sourceAssets = assets
        nextScanIndex = 0
        self.assets = []
        hasMoreAssets = !assets.isEmpty

        guard !assets.isEmpty else {
            return
        }

        Task {
            await loadNextPage(for: sessionID)
        }
    }

    func reset() {
        sessionID = UUID()
        sourceAssets = []
        nextScanIndex = 0
        assets = []
        hasMoreAssets = false
        isLoading = false
    }

    func loadMoreIfNeeded(currentAssetID: String?) {
        guard !isLoading, hasMoreAssets else {
            return
        }

        if assets.isEmpty {
            Task {
                await loadNextPage(for: sessionID)
            }
            return
        }

        guard let currentAssetID,
              let currentIndex = assets.firstIndex(where: { $0.id == currentAssetID }) else {
            return
        }

        let thresholdIndex = max(assets.count - Self.prefetchThreshold, 0)
        guard currentIndex >= thresholdIndex else {
            return
        }

        Task {
            await loadNextPage(for: sessionID)
        }
    }

    private func loadNextPage(for sessionID: UUID) async {
        guard sessionID == self.sessionID, !isLoading else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        var matchedAssets: [PhotoAsset] = []

        while matchedAssets.count < Self.pageSize, nextScanIndex < sourceAssets.count {
            let batchEnd = min(nextScanIndex + Self.scanBatchSize, sourceAssets.count)
            let assetBatch = Array(sourceAssets[nextScanIndex..<batchEnd])
            nextScanIndex = batchEnd

            let localAssetIDs = await PhotoLoader.locallyAvailableAssetIDs(from: assetBatch)
            guard !Task.isCancelled, sessionID == self.sessionID else {
                return
            }

            matchedAssets.append(contentsOf: assetBatch.filter { localAssetIDs.contains($0.id) })
        }

        if !matchedAssets.isEmpty {
            assets.append(contentsOf: matchedAssets)
        }

        hasMoreAssets = nextScanIndex < sourceAssets.count
    }
}

struct SettingsTabView: View {
    @Binding var readOnlyMode: Bool
    @Binding var allowsICloudDownload: Bool
    @Binding var showsOnlyLocalPhotos: Bool
    #if os(iOS)
    let authorizationState: PhotoLibraryViewModel.AuthorizationState
    let localPhotosSummary: String?
    let localPhotosSummaryState: PhotoLibraryViewModel.LocalPhotosSummaryState?
    let localPhotosCount: Int?
    let localAlbumsCount: Int?
    let localPhotosSummaryDestination: AppTab?
    let onOpenLocalPhotosSummary: (() -> Void)?
    @Environment(\.openURL) private var openURL
    @State private var showsICloudDownloadExplanation = false
    #else
    init(
        readOnlyMode: Binding<Bool>,
        allowsICloudDownload: Binding<Bool>,
        showsOnlyLocalPhotos: Binding<Bool>
    ) {
        self._readOnlyMode = readOnlyMode
        self._allowsICloudDownload = allowsICloudDownload
        self._showsOnlyLocalPhotos = showsOnlyLocalPhotos
    }
    #endif
    
    #if os(iOS)
    init(
        readOnlyMode: Binding<Bool>,
        authorizationState: PhotoLibraryViewModel.AuthorizationState,
        localPhotosSummary: String?,
        localPhotosSummaryState: PhotoLibraryViewModel.LocalPhotosSummaryState?,
        localPhotosCount: Int?,
        localAlbumsCount: Int?,
        localPhotosSummaryDestination: AppTab?,
        onOpenLocalPhotosSummary: (() -> Void)? = nil,
        allowsICloudDownload: Binding<Bool>,
        showsOnlyLocalPhotos: Binding<Bool>
    ) {
        self._readOnlyMode = readOnlyMode
        self.authorizationState = authorizationState
        self.localPhotosSummary = localPhotosSummary
        self.localPhotosSummaryState = localPhotosSummaryState
        self.localPhotosCount = localPhotosCount
        self.localAlbumsCount = localAlbumsCount
        self.localPhotosSummaryDestination = localPhotosSummaryDestination
        self.onOpenLocalPhotosSummary = onOpenLocalPhotosSummary
        self._allowsICloudDownload = allowsICloudDownload
        self._showsOnlyLocalPhotos = showsOnlyLocalPhotos
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

                Section(
                    header: Text("iCloud 照片"),
                    footer: Text("部分照片开启 iCloud 照片后只保存在云端。关闭联网下载时，应用不会主动联网；如果只想离线查看，可以打开“仅显示已下载到本地的照片”，先去系统相册下载好再回来。")
                ) {
                    Toggle("允许联网下载 iCloud 原图", isOn: iCloudDownloadBinding)
                    Toggle("仅显示已下载到本地的照片", isOn: $showsOnlyLocalPhotos)

                    #if os(iOS)
                    if showsOnlyLocalPhotos, let localPhotosSummary {
                        if let onOpenLocalPhotosSummary {
            LocalPhotosSummaryButton(
                summary: localPhotosSummary,
                state: localPhotosSummaryState,
                localPhotosCount: localPhotosCount,
                                localAlbumsCount: localAlbumsCount,
                                iconName: summaryDestinationIconName,
                                accessibilityHint: summaryDestinationAccessibilityHint,
                                action: onOpenLocalPhotosSummary
                            )
                        } else {
                            Text(localPhotosSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    #endif
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
            #if os(iOS)
            .alert("允许联网下载 iCloud 原图？", isPresented: $showsICloudDownloadExplanation) {
                Button("保持离线", role: .cancel) { }
                Button("允许下载") {
                    allowsICloudDownload = true
                }
            } message: {
                Text("有些照片的原图和 Exif 只存在 iCloud，应用需要短暂联网把原图下载到本机后才能读取。你也可以继续保持离线，只查看已经在本地的照片。")
            }
            #endif
        }
    }
    
    #if os(iOS)
    private var showsSettingsShortcut: Bool {
        authorizationState != .unknown
    }

    private var iCloudDownloadBinding: Binding<Bool> {
        Binding(
            get: { allowsICloudDownload },
            set: { newValue in
                if newValue {
                    showsICloudDownloadExplanation = true
                } else {
                    allowsICloudDownload = false
                }
            }
        )
    }

    private var summaryDestinationIconName: String {
        switch localPhotosSummaryDestination {
        case .albums:
            return "rectangle.stack"
        case .photos:
            return "photo.on.rectangle.angled"
        case .search:
            return "magnifyingglass"
        case .settings, .picker, .none:
            return "arrow.up.forward"
        }
    }

    private var summaryDestinationAccessibilityHint: String {
        switch localPhotosSummaryDestination {
        case .albums:
            return "打开相册页面查看本地照片统计"
        case .photos:
            return "打开图库页面继续加载本地照片"
        case .search:
            return "打开搜索页面查看本地照片"
        case .settings, .picker, .none:
            return "打开相关页面查看本地照片状态"
        }
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

private struct LocalPhotosSummaryButton: View {
    let summary: String
    let state: PhotoLibraryViewModel.LocalPhotosSummaryState?
    let localPhotosCount: Int?
    let localAlbumsCount: Int?
    let iconName: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                statusPulse

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        countChip(title: "本地", value: localPhotosCount)

                        if showsAlbumCount {
                            countChip(title: "相册", value: localAlbumsCount)
                        }
                    }

                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 8)

                Image(systemName: iconName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce.byLayer, value: summary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
        .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: localPhotosCount)
        .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: localAlbumsCount)
        .animation(.easeInOut(duration: 0.2), value: summary)
    }

    private var showsAlbumCount: Bool {
        switch state {
        case .buildingAlbums, .complete:
            return true
        case .loading, .paginating, .none:
            return localAlbumsCount != nil && localAlbumsCount != 0
        }
    }

    private var statusPulse: some View {
        Circle()
            .fill(statusColor.gradient)
            .frame(width: 10, height: 10)
            .overlay {
                Circle()
                    .stroke(statusColor.opacity(0.25), lineWidth: 8)
                    .scaleEffect(needsPulse ? 1.18 : 1)
                    .opacity(needsPulse ? 1 : 0.35)
            }
            .animation(
                needsPulse ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .easeOut(duration: 0.2),
                value: needsPulse
            )
    }

    @ViewBuilder
    private func countChip(title: String, value: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatted(value))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value ?? 0)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch state {
        case .complete:
            return .green
        case .loading, .paginating, .buildingAlbums, .none:
            return .orange
        }
    }

    private var needsPulse: Bool {
        switch state {
        case .complete:
            return false
        case .loading, .paginating, .buildingAlbums, .none:
            return true
        }
    }

    private func formatted(_ value: Int?) -> String {
        guard let value else {
            return "0"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct LibraryAuthorizationContent<Content: View>: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let emptyTitle: String
    @ViewBuilder let content: Content
    
    var body: some View {
        Group {
            if library.isFilteringLocalAssets && library.assets.isEmpty {
                ProgressView("正在筛选已下载到本地的照片")
            } else {
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
                    description: Text(emptyStateDescription)
                )
            }
            }
        }
    }

    private var emptyStateDescription: String {
        if library.showsOnlyLocalAssets {
            return "当前只显示已经下载到本地的照片。可以先去系统相册下载原图，或到设置里关闭这个筛选。"
        }

        return "当前权限范围内没有照片。"
    }
}

struct PhotoAssetGridView: View {
    let assets: [PhotoAsset]
    let readOnlyMode: Bool
    let isLoadingMore: Bool
    let onAssetAppear: ((String?) -> Void)?
    let onRefresh: (() async -> Void)?
    
    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]
    
    init(
        assets: [PhotoAsset],
        readOnlyMode: Bool,
        isLoadingMore: Bool = false,
        onAssetAppear: ((String?) -> Void)? = nil,
        onRefresh: (() async -> Void)? = nil
    ) {
        self.assets = assets
        self.readOnlyMode = readOnlyMode
        self.isLoadingMore = isLoadingMore
        self.onAssetAppear = onAssetAppear
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
                    .onAppear {
                        onAssetAppear?(asset.id)
                    }
                }

                if isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .gridCellColumns(columns.count)
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
