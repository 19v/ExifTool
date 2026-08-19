#if os(iOS)

import Photos
internal import PhotosUI
import SwiftUI
import UIKit

struct IOSRootView: View {
    @State private var library = PhotoLibraryViewModel()
    @State private var sharedPhotoAsset: PhotoAsset?
    @State private var presentedFileURLToCleanup: URL?
    @State private var isRequestingLibraryAccess = false
    @State private var isPresentingLimitedLibraryPicker = false
    @State private var isPresentingSettings = false
    @State private var presentsLimitedLibraryPickerAfterSettingsDismissal = false
    @AppStorage("allowsICloudDownload") private var allowsICloudDownload = false
    @AppStorage("showsOnlyLocalPhotos") private var showsOnlyLocalPhotos = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        IOSLibraryBrowserView(
            library: library,
            onRequestPhotoPermission: requestLibraryAccess,
            onPresentLimitedLibraryPicker: presentLimitedLibraryPicker,
            onPresentSettings: { isPresentingSettings = true }
        )
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
                    initialAssetID: asset.id
                )
            }
        }
        .sheet(isPresented: $isPresentingSettings, onDismiss: finishSettingsPresentation) {
            IOSSettingsTabView(
                accessScope: library.accessScope,
                authorizationState: library.authorizationState,
                localPhotosSummarySnapshot: library.localPhotosSummarySnapshot,
                onOpenLocalPhotosSummary: showsLibrary ? { isPresentingSettings = false } : nil,
                onRequestPhotoPermission: requestLibraryAccess,
                onPresentLimitedLibraryPicker: queueLimitedLibraryPickerAfterSettings,
                allowsICloudDownload: $allowsICloudDownload,
                showsOnlyLocalPhotos: $showsOnlyLocalPhotos
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .background {
            LimitedLibraryPickerPresenter(isPresented: $isPresentingLimitedLibraryPicker) {
                Task {
                    await library.refresh()
                }
            }
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

    private var showsLibrary: Bool {
        library.accessScope == .full ||
            (library.accessScope == .limited && library.authorizationState != .empty)
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

    private func queueLimitedLibraryPickerAfterSettings() {
        presentsLimitedLibraryPickerAfterSettingsDismissal = true
        isPresentingSettings = false
    }

    private func finishSettingsPresentation() {
        guard presentsLimitedLibraryPickerAfterSettingsDismissal else {
            return
        }
        presentsLimitedLibraryPickerAfterSettingsDismissal = false
        presentLimitedLibraryPicker()
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
            return
        }

        presentedFileURLToCleanup = asset.localFile?.fileURL
        sharedPhotoAsset = asset
    }

    private func openSharedPhoto(from url: URL) {
        guard let fileName = SharedPhotoImport.fileName(from: url),
              let fileURL = SharedPhotoImport.fileURL(forSharedFileName: fileName),
              let asset = PhotoFileImporter.importAsset(from: fileURL) else {
            return
        }

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
