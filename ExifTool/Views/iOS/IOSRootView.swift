#if os(iOS)

import Photos
internal import PhotosUI
import SwiftUI
import UIKit

struct IOSRootView: View {
    private enum LibraryNavigationMode {
        case pickerOnly
        case limitedLibrary
        case fullLibrary
    }

    @State private var library = PhotoLibraryViewModel()
    @State private var selectedTab = AppTab.picker
    @State private var sharedPhotoAsset: PhotoAsset?
    @State private var presentedFileURLToCleanup: URL?
    @State private var isRequestingLibraryAccess = false
    @State private var isPresentingLimitedLibraryPicker = false
    @AppStorage("readOnlyMode") private var readOnlyMode = true
    @AppStorage("allowsICloudDownload") private var allowsICloudDownload = false
    @AppStorage("showsOnlyLocalPhotos") private var showsOnlyLocalPhotos = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            if showsLibraryTabs {
                Tab("图库", systemImage: "photo.on.rectangle.angled", value: AppTab.photos) {
                    PhotoPickerTabView(
                        library: library,
                        readOnlyMode: readOnlyMode,
                        onPresentLimitedLibraryPicker: presentLimitedLibraryPicker
                    )
                }

                if showsAlbumsTab {
                    Tab("相册", systemImage: "rectangle.stack", value: AppTab.albums) {
                        AlbumsTabView(library: library, readOnlyMode: readOnlyMode)
                    }
                }

                Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                    settingsView
                }

                if showsSearchTab {
                    Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                        SearchTabView(library: library, readOnlyMode: readOnlyMode)
                    }
                }
            } else {
                Tab("选图", systemImage: "plus.square.on.square", value: AppTab.picker) {
                    ManualPhotoPickerTabView(
                        readOnlyMode: readOnlyMode,
                        authorizationState: library.authorizationState,
                        onRequestPhotoPermission: requestLibraryAccess
                    )
                }

                Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                    settingsView
                }
            }
        }
        .task {
            PhotoTemporaryFileStore.cleanupStaleFiles()
            SharedPhotoImport.cleanupStaleFiles()
            await library.prepare(showingOnlyLocalAssets: showsOnlyLocalPhotos)
        }
        .onOpenURL { url in
            openIncomingPhoto(from: url)
        }
        .sheet(item: $sharedPhotoAsset, onDismiss: cleanupPresentedFile) { asset in
            NavigationStack {
                PhotoDetailView(
                    assets: [asset],
                    initialAssetID: asset.id,
                    readOnlyMode: readOnlyMode
                )
            }
        }
        .background {
            LimitedLibraryPickerPresenter(isPresented: $isPresentingLimitedLibraryPicker) {
                Task {
                    await library.refresh()
                }
            }
        }
        .onAppear {
            syncSelectedTab()
        }
        .onChange(of: library.accessScope) { _, _ in
            syncSelectedTab()
        }
        .onChange(of: showsOnlyLocalPhotos) { _, isEnabled in
            Task {
                await library.setShowsOnlyLocalAssets(isEnabled)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            library.applicationDidBecomeActive()
        }
    }

    private var settingsView: some View {
        IOSSettingsTabView(
            readOnlyMode: $readOnlyMode,
            accessScope: library.accessScope,
            authorizationState: library.authorizationState,
            localPhotosSummarySnapshot: library.localPhotosSummarySnapshot,
            localPhotosSummaryDestination: localPhotosSummaryDestination,
            onOpenLocalPhotosSummary: openLocalPhotosSummary,
            onRequestPhotoPermission: requestLibraryAccess,
            onPresentLimitedLibraryPicker: presentLimitedLibraryPicker,
            allowsICloudDownload: $allowsICloudDownload,
            showsOnlyLocalPhotos: $showsOnlyLocalPhotos
        )
    }

    private var showsLibraryTabs: Bool {
        navigationMode != .pickerOnly
    }

    private var showsAlbumsTab: Bool {
        navigationMode == .fullLibrary
    }

    private var showsSearchTab: Bool {
        navigationMode != .pickerOnly
    }

    private var navigationMode: LibraryNavigationMode {
        switch library.accessScope {
        case .full:
            return .fullLibrary
        case .limited:
            return library.authorizationState == .empty ? .pickerOnly : .limitedLibrary
        case .unknown, .denied:
            return .pickerOnly
        }
    }

    private func syncSelectedTab() {
        if showsLibraryTabs {
            if selectedTab == .picker || (selectedTab == .albums && !showsAlbumsTab) {
                selectedTab = .photos
            }
        } else if selectedTab != .picker && selectedTab != .settings {
            selectedTab = .picker
        }
    }

    private func requestLibraryAccess() {
        guard !isRequestingLibraryAccess else {
            return
        }

        isRequestingLibraryAccess = true
        Task {
            await library.requestAccess(showingOnlyLocalAssets: showsOnlyLocalPhotos)
            isRequestingLibraryAccess = false
        }
    }

    private func presentLimitedLibraryPicker() {
        isPresentingLimitedLibraryPicker = true
    }

    private var localPhotosSummaryDestination: AppTab? {
        guard showsOnlyLocalPhotos else {
            return nil
        }

        if library.isBuildingLocalAlbumStats && showsAlbumsTab {
            return .albums
        }

        if showsLibraryTabs {
            return .photos
        }

        return .settings
    }

    private func openLocalPhotosSummary() {
        guard let destination = localPhotosSummaryDestination else {
            return
        }

        selectedTab = destination
    }

    private func openIncomingPhoto(from url: URL) {
        if url.isFileURL {
            openDocumentPhoto(from: url)
        } else {
            openSharedPhoto(from: url)
        }
    }

    private func openDocumentPhoto(from url: URL) {
        let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let asset = PhotoFileImporter.importAssetCopyingToTemporaryStorage(from: url) else {
            selectedTab = fallbackTabAfterSharedPhotoDismissal
            return
        }

        selectedTab = fallbackTabAfterSharedPhotoDismissal
        presentedFileURLToCleanup = asset.localFile?.fileURL
        sharedPhotoAsset = asset
    }

    private func openSharedPhoto(from url: URL) {
        guard let fileName = SharedPhotoImport.fileName(from: url),
              let fileURL = SharedPhotoImport.fileURL(forSharedFileName: fileName),
              let asset = PhotoFileImporter.importAsset(from: fileURL) else {
            selectedTab = fallbackTabAfterSharedPhotoDismissal
            return
        }

        selectedTab = fallbackTabAfterSharedPhotoDismissal
        presentedFileURLToCleanup = fileURL
        sharedPhotoAsset = asset
    }

    private func cleanupPresentedFile() {
        guard let presentedFileURLToCleanup else {
            return
        }

        PhotoTemporaryFileStore.removeIfManaged(presentedFileURLToCleanup)
        SharedPhotoImport.removeSharedFile(at: presentedFileURLToCleanup)
        self.presentedFileURLToCleanup = nil
    }

    private var fallbackTabAfterSharedPhotoDismissal: AppTab {
        showsLibraryTabs ? .photos : .picker
    }
}

private struct LimitedLibraryPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCompletion: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented,
              !context.coordinator.isPresenting,
              viewController.viewIfLoaded?.window != nil else {
            return
        }

        context.coordinator.isPresenting = true
        let coordinator = context.coordinator
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController) { _ in
            Task { @MainActor in
                coordinator.finishPresentation()
            }
        }
    }

    @MainActor
    final class Coordinator {
        var parent: LimitedLibraryPickerPresenter
        var isPresenting = false

        init(parent: LimitedLibraryPickerPresenter) {
            self.parent = parent
        }

        func finishPresentation() {
            isPresenting = false
            parent.isPresented = false
            parent.onCompletion()
        }
    }
}

#endif
