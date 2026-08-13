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
    @State private var pager: LocalAssetPagingViewModel

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
                onAssetAppear: assetAppearHandler,
                onRequestPhotoPermission: onRequestPhotoPermission
            )
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    LibraryFilterMenu(
                        filter: $filter,
                        years: library.availableYears,
                        albums: library.albums,
                        isEnabled: showsLibrary,
                        showsLimitedLibraryAction: library.accessScope == .limited,
                        onPresentLimitedLibraryPicker: onPresentLimitedLibraryPicker
                    )

                    Button(action: onPresentSettings) {
                        Label("设置", systemImage: "gearshape")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let statusSnapshot {
                    LocalPhotosStatusBanner(snapshot: statusSnapshot, emphasis: .floating)
                }
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

private struct LibraryFilterMenu: View {
    @Binding var filter: LibraryFilter
    let years: [Int]
    let albums: [PhotoAlbum]
    let isEnabled: Bool
    let showsLimitedLibraryAction: Bool
    let onPresentLimitedLibraryPicker: (() -> Void)?

    var body: some View {
        Menu {
            Button {
                filter = .all
            } label: {
                FilterMenuLabel(
                    title: AppLocalization.string("全部照片"),
                    systemImage: filter == .all ? "checkmark" : "photo.on.rectangle.angled"
                )
            }

            if !years.isEmpty {
                Menu("年份") {
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
            }

            if !albums.isEmpty {
                Menu("相册") {
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
            }

            if showsLimitedLibraryAction {
                Divider()
                Button("重新选择照片") {
                    onPresentLimitedLibraryPicker?()
                }
            }
        } label: {
            Label("筛选", systemImage: "line.3.horizontal.decrease")
        }
        .disabled(!isEnabled)
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

private struct FilterMenuLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
    }
}

#endif
