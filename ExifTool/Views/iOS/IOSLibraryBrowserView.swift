#if os(iOS)

import SwiftUI

struct IOSLibraryBrowserView: View {
    let library: PhotoLibraryViewModel
    let readOnlyMode: Bool
    let onRequestPhotoPermission: (() -> Void)?
    let onPresentLimitedLibraryPicker: (() -> Void)?
    let onPresentSettings: () -> Void

    @State private var filter: LibraryFilter = .all
    @State private var filteredAssets: [PhotoAsset] = []
    @State private var isLoadingFilter = false
    @State private var surpriseAsset: PhotoAsset?
    @State private var isLoadingSurprise = false
    @State private var showsNoSurprisePhotoAlert = false
    @State private var pager: LocalAssetPagingViewModel
    @AppStorage("libraryPhotoSortOrder") private var sortOrder: PhotoAssetSortOrder = .oldestFirst

    init(
        library: PhotoLibraryViewModel,
        readOnlyMode: Bool,
        onRequestPhotoPermission: (() -> Void)?,
        onPresentLimitedLibraryPicker: (() -> Void)?,
        onPresentSettings: @escaping () -> Void
    ) {
        self.library = library
        self.readOnlyMode = readOnlyMode
        self.onRequestPhotoPermission = onRequestPhotoPermission
        self.onPresentLimitedLibraryPicker = onPresentLimitedLibraryPicker
        self.onPresentSettings = onPresentSettings
        _pager = State(initialValue: LocalAssetPagingViewModel { assets in
            await library.localAvailabilityIndex.locallyAvailableIDs(in: assets)
        })
    }

    var body: some View {
        NavigationStack {
            IOSLibraryBrowserContent(
                showsLibrary: showsLibrary,
                library: library,
                readOnlyMode: readOnlyMode,
                hasActiveFilter: filter != .all,
                assets: displayedAssets,
                isLoadingFilter: isLoadingFilter,
                isLoadingMore: isLoadingMore,
                sortOrder: sortOrder,
                onAssetAppear: assetAppearHandler,
                onRequestPhotoPermission: onRequestPhotoPermission
            )
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: showSurprisePhoto) {
                        if isLoadingSurprise {
                            ProgressView()
                        } else {
                            Label("随机照片", systemImage: "dice")
                        }
                    }
                    .disabled(!showsLibrary || isLoadingSurprise)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarButton(action: onPresentSettings)
                }

                if showsLibrary {
                    LibraryFilterToolbarContent(
                        filter: $filter,
                        years: library.availableYears,
                        albums: library.albums,
                        sortOrder: $sortOrder,
                        showsLimitedLibraryAction: library.accessScope == .limited,
                        onPresentLimitedLibraryPicker: onPresentLimitedLibraryPicker
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let statusSnapshot {
                    LocalPhotosStatusBanner(snapshot: statusSnapshot, emphasis: .floating)
                }
            }
            .navigationDestination(item: $surpriseAsset) { asset in
                PhotoDetailView(
                    assets: [asset],
                    initialAssetID: asset.id,
                    readOnlyMode: readOnlyMode
                )
            }
            .alert("没有可随机展示的照片", isPresented: $showsNoSurprisePhotoAlert) {
                Button("好", role: .cancel) { }
            }
            .task(id: reloadRevision) {
                await reloadFilteredAssets()
            }
            .task(id: localAlbumStatsRevision) {
                if library.showsOnlyLocalAssets {
                    library.buildRemainingLocalAlbumStatsIfNeeded()
                }
            }
            .onChange(of: library.accessScope) { _, newScope in
                if newScope != .full, case .album = filter {
                    filter = .all
                }
            }
        }
    }

    private var showsLibrary: Bool {
        library.accessScope == .full ||
            (library.accessScope == .limited && library.authorizationState != .empty)
    }

    private var displayedAssets: [PhotoAsset] {
        guard filter != .all else {
            return library.assets
        }
        return library.showsOnlyLocalAssets ? pager.assets : filteredAssets
    }

    private var isLoadingMore: Bool {
        guard library.showsOnlyLocalAssets else {
            return false
        }
        return filter == .all ? library.hasMoreLocalAssets : pager.hasMoreAssets
    }

    private var assetAppearHandler: ((String?) -> Void)? {
        guard library.showsOnlyLocalAssets else {
            return nil
        }
        return filter == .all
            ? library.loadMoreLocalAssetsIfNeeded
            : pager.loadMoreIfNeeded
    }

    private var navigationTitle: String {
        switch filter {
        case .all:
            return AppLocalization.string("图库")
        case .year(let year):
            return localizedYear(year)
        case .album(let albumID):
            return library.albums.first(where: { $0.id == albumID })?.title
                ?? AppLocalization.string("图库")
        }
    }

    private var statusSnapshot: LocalPhotosStatusSnapshot? {
        filter == .all
            ? library.localPhotosPickerBannerSnapshot
            : library.localPhotosAlbumBannerSnapshot
    }

    private var reloadRevision: LibraryFilterReloadRevision {
        let albumRevision: Int
        if case .album(let albumID) = filter {
            albumRevision = library.albumContentRevisions[albumID]
        } else {
            albumRevision = 0
        }
        return LibraryFilterReloadRevision(
            filter: filter,
            assetCollectionRevision: library.assetCollectionRevision,
            albumContentRevision: albumRevision,
            showsOnlyLocalAssets: library.showsOnlyLocalAssets
        )
    }

    private var localAlbumStatsRevision: LocalAlbumStatsRevision {
        LocalAlbumStatsRevision(
            showsOnlyLocalAssets: library.showsOnlyLocalAssets,
            assetCollectionRevision: library.assetCollectionRevision
        )
    }

    private func reloadFilteredAssets() async {
        let requestedFilter = filter
        guard requestedFilter != .all else {
            filteredAssets = []
            pager.reset()
            isLoadingFilter = false
            return
        }

        isLoadingFilter = true
        let assets: [PhotoAsset]
        switch requestedFilter {
        case .all:
            assets = []
        case .year(let year):
            guard let interval = yearInterval(for: year) else {
                assets = []
                break
            }
            assets = await PhotoLibraryViewModel.fetchImageAssetsOffMain(in: interval)
        case .album(let albumID):
            guard let album = library.albums.first(where: { $0.id == albumID }) else {
                if filter == requestedFilter {
                    filter = .all
                    isLoadingFilter = false
                }
                return
            }
            assets = await PhotoLibraryViewModel.fetchImageAssetsOffMain(in: album.collection)
        }

        guard !Task.isCancelled, filter == requestedFilter else {
            return
        }
        filteredAssets = assets
        if library.showsOnlyLocalAssets {
            pager.setSourceAssets(assets)
        } else {
            pager.reset()
        }
        isLoadingFilter = false
    }

    private func showSurprisePhoto() {
        guard !isLoadingSurprise else {
            return
        }
        isLoadingSurprise = true
        Task {
            let asset = await library.surpriseAsset()
            isLoadingSurprise = false
            if let asset {
                surpriseAsset = asset
            } else {
                showsNoSurprisePhotoAlert = true
            }
        }
    }

    private func yearInterval(for year: Int) -> DateInterval? {
        var components = DateComponents()
        components.calendar = .current
        components.year = year
        components.month = 1
        components.day = 1
        guard let start = components.date,
              let end = Calendar.current.date(byAdding: .year, value: 1, to: start) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func localizedYear(_ year: Int) -> String {
        guard let interval = yearInterval(for: year) else {
            return String(year)
        }
        return interval.start.formatted(.dateTime.year())
    }
}

private enum LibraryFilter: Hashable {
    case all
    case year(Int)
    case album(String)
}

private struct LibraryFilterReloadRevision: Equatable {
    let filter: LibraryFilter
    let assetCollectionRevision: Int
    let albumContentRevision: Int
    let showsOnlyLocalAssets: Bool
}

private struct LocalAlbumStatsRevision: Equatable {
    let showsOnlyLocalAssets: Bool
    let assetCollectionRevision: Int
}

private struct IOSLibraryBrowserContent: View {
    let showsLibrary: Bool
    let library: PhotoLibraryViewModel
    let readOnlyMode: Bool
    let hasActiveFilter: Bool
    let assets: [PhotoAsset]
    let isLoadingFilter: Bool
    let isLoadingMore: Bool
    let sortOrder: PhotoAssetSortOrder
    let onAssetAppear: ((String?) -> Void)?
    let onRequestPhotoPermission: (() -> Void)?

    var body: some View {
        if showsLibrary {
            LibraryAuthorizationContent(library: library, emptyTitle: "没有可显示的照片") {
                if hasActiveFilter && assets.isEmpty && (isLoadingFilter || isLoadingMore) {
                    ProgressView("正在载入照片")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasActiveFilter && assets.isEmpty {
                    ContentUnavailableView(
                        "没有符合筛选条件的照片",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                } else {
                    PhotoAssetGridView(
                        assets: assets,
                        readOnlyMode: readOnlyMode,
                        showsReadOnlyOverlay: false,
                        isLoadingMore: isLoadingMore,
                        sortOrder: sortOrder,
                        onAssetAppear: onAssetAppear,
                        onRefresh: library.refresh
                    )
                }
            }
        } else {
            ManualPhotoPickerView(
                readOnlyMode: readOnlyMode,
                authorizationState: library.authorizationState,
                onRequestPhotoPermission: onRequestPhotoPermission
            )
        }
    }
}

private struct SettingsToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("设置", systemImage: "gearshape")
        }
    }
}

private struct LibraryFilterToolbarContent: ToolbarContent {
    @Binding var filter: LibraryFilter
    let years: [Int]
    let albums: [PhotoAlbum]
    @Binding var sortOrder: PhotoAssetSortOrder
    let showsLimitedLibraryAction: Bool
    let onPresentLimitedLibraryPicker: (() -> Void)?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            LibraryYearFilterMenu(filter: $filter, years: years)

            Spacer()

            LibraryAlbumFilterMenu(
                filter: $filter,
                albums: albums,
                showsLimitedLibraryAction: showsLimitedLibraryAction,
                onPresentLimitedLibraryPicker: onPresentLimitedLibraryPicker
            )

            Spacer()

            LibrarySortMenu(sortOrder: $sortOrder)
        }
    }
}

private struct LibraryYearFilterMenu: View {
    @Binding var filter: LibraryFilter
    let years: [Int]

    var body: some View {
        Menu {
            AllPhotosFilterButton(filter: $filter)

            if !years.isEmpty {
                Divider()
                ForEach(years, id: \.self) { year in
                    Button {
                        filter = .year(year)
                    } label: {
                        FilterMenuLabel(
                            title: localizedYear(year),
                            systemImage: filter == .year(year) ? "checkmark" : "calendar"
                        )
                    }
                }
            }
        } label: {
            ToolbarFilterLabel(
                title: selectedYear.map(localizedYear) ?? AppLocalization.string("时间"),
                systemImage: "calendar"
            )
        }
        .disabled(years.isEmpty && selectedYear == nil)
    }

    private var selectedYear: Int? {
        guard case .year(let year) = filter else {
            return nil
        }
        return year
    }

    private func localizedYear(_ year: Int) -> String {
        var components = DateComponents()
        components.calendar = .current
        components.year = year
        components.month = 1
        components.day = 1
        return components.date?.formatted(.dateTime.year()) ?? String(year)
    }
}

private struct LibraryAlbumFilterMenu: View {
    @Binding var filter: LibraryFilter
    let albums: [PhotoAlbum]
    let showsLimitedLibraryAction: Bool
    let onPresentLimitedLibraryPicker: (() -> Void)?

    var body: some View {
        Menu {
            AllPhotosFilterButton(filter: $filter)

            if !albums.isEmpty {
                Divider()
                ForEach(albums) { album in
                    Button {
                        filter = .album(album.id)
                    } label: {
                        FilterMenuLabel(
                            title: album.title,
                            systemImage: filter == .album(album.id) ? "checkmark" : "rectangle.stack"
                        )
                    }
                }
            }

            if showsLimitedLibraryAction {
                Divider()
                Button("重新选择照片") {
                    onPresentLimitedLibraryPicker?()
                }
            }
        } label: {
            ToolbarFilterLabel(
                title: selectedAlbumTitle ?? AppLocalization.string("相册"),
                systemImage: "rectangle.stack"
            )
        }
        .disabled(albums.isEmpty && !showsLimitedLibraryAction && selectedAlbumTitle == nil)
    }

    private var selectedAlbumTitle: String? {
        guard case .album(let albumID) = filter else {
            return nil
        }
        return albums.first(where: { $0.id == albumID })?.title
    }
}

private struct LibrarySortMenu: View {
    @Binding var sortOrder: PhotoAssetSortOrder

    var body: some View {
        Menu {
            Button {
                sortOrder = .oldestFirst
            } label: {
                FilterMenuLabel(
                    title: AppLocalization.string("按拍摄时间(旧到新)"),
                    systemImage: sortOrder == .oldestFirst ? "checkmark" : "arrow.down"
                )
            }

            Button {
                sortOrder = .newestFirst
            } label: {
                FilterMenuLabel(
                    title: AppLocalization.string("按拍摄时间(新到旧)"),
                    systemImage: sortOrder == .newestFirst ? "checkmark" : "arrow.up"
                )
            }
        } label: {
            ToolbarFilterLabel(
                title: AppLocalization.string("排序"),
                systemImage: "arrow.up.arrow.down"
            )
        }
    }
}

private struct ToolbarFilterLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
    }
}

private struct AllPhotosFilterButton: View {
    @Binding var filter: LibraryFilter

    var body: some View {
        Button {
            filter = .all
        } label: {
            FilterMenuLabel(
                title: AppLocalization.string("全部照片"),
                systemImage: filter == .all ? "checkmark" : "photo.on.rectangle.angled"
            )
        }
    }
}

private struct FilterMenuLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}

#endif
