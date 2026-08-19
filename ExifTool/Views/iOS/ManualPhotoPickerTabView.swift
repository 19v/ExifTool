#if os(iOS)

internal import PhotosUI
import SwiftUI

struct ManualPhotoPickerView: View {
    let authorizationState: PhotoLibraryViewModel.AuthorizationState
    let onRequestPhotoPermission: (() -> Void)?

    @AppStorage("hasShownInitialPhotoLibraryAuthorizationCTA")
    private var hasShownInitialPhotoLibraryAuthorizationCTA = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedAssetForDetail: PhotoAsset?
    @State private var temporaryFileURLToCleanup: URL?
    @State private var showsImportingDialog = false
    @State private var importProgressTitle = AppLocalization.string("manualPicker.readingImage")
    @State private var importProgressFraction: Double?
    @State private var importErrorMessage: String?
    @State private var showsInitialAuthorizationCTAThisSession = false

    var body: some View {
        ManualPhotoPickerEmptyState(
            selectedItems: $selectedItems,
            showsAuthorizationCTA: shouldShowInitialAuthorizationCTA,
            onRequestPhotoPermission: onRequestPhotoPermission
        )
        .onAppear(perform: updateInitialAuthorizationCTA)
        .onChange(of: authorizationState) { _, newValue in
            if newValue != .unknown {
                showsInitialAuthorizationCTAThisSession = false
            }
        }
        .sheet(item: $selectedAssetForDetail, onDismiss: cleanupPresentedTemporaryFile) { asset in
            NavigationStack {
                PhotoDetailView(
                    assets: [asset],
                    initialAssetID: asset.id
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if showsImportingDialog {
                ManualPhotoImportProgressOverlay(
                    title: importProgressTitle,
                    fraction: importProgressFraction
                )
            }
        }
        .task(id: selectedItems.map(\.hashValue)) {
            await importSelectedItems()
        }
        .alert("导入失败", isPresented: errorBinding) {
            Button("知道了") {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? AppLocalization.string("manualPicker.importFailure"))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { importErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    importErrorMessage = nil
                }
            }
        )
    }

    private var shouldShowInitialAuthorizationCTA: Bool {
        authorizationState == .unknown && showsInitialAuthorizationCTAThisSession
    }

    private func updateInitialAuthorizationCTA() {
        guard authorizationState == .unknown else {
            showsInitialAuthorizationCTAThisSession = false
            return
        }

        if !hasShownInitialPhotoLibraryAuthorizationCTA {
            showsInitialAuthorizationCTAThisSession = true
            hasShownInitialPhotoLibraryAuthorizationCTA = true
        }
    }

    private func importSelectedItems() async {
        guard !selectedItems.isEmpty else {
            return
        }

        defer {
            showsImportingDialog = false
            importProgressFraction = nil
            selectedItems = []
        }

        importErrorMessage = nil
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(selectedItems.count)

        for (index, item) in selectedItems.enumerated() {
            do {
                let asset = try await PhotosPickerPhotoImporter.importAsset(from: item, index: index) { phase in
                    switch phase {
                    case .reading:
                        importProgressTitle = AppLocalization.string("manualPicker.readingImage")
                        importProgressFraction = nil
                    case .downloadingOriginal(let progress):
                        importProgressTitle = AppLocalization.string("manualPicker.downloadingOriginal")
                        importProgressFraction = progress
                    }
                    showsImportingDialog = true
                }
                assets.append(asset)
            } catch let error as LocalizedError {
                importErrorMessage = error.errorDescription ?? AppLocalization.string("manualPicker.partialFailure")
            } catch {
                importErrorMessage = AppLocalization.string("manualPicker.partialFailure")
            }
        }

        if let firstAsset = assets.first {
            temporaryFileURLToCleanup = firstAsset.localFile?.fileURL
            selectedAssetForDetail = firstAsset
        } else if importErrorMessage == nil {
            importErrorMessage = AppLocalization.string("manualPicker.noReadableImages")
        }
    }

    private func cleanupPresentedTemporaryFile() {
        if let temporaryFileURLToCleanup {
            PhotoTemporaryFileStore.removeIfManaged(temporaryFileURLToCleanup)
        }
        temporaryFileURLToCleanup = nil
    }
}

private struct ManualPhotoPickerEmptyState: View {
    @Binding var selectedItems: [PhotosPickerItem]
    let showsAuthorizationCTA: Bool
    let onRequestPhotoPermission: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 1,
                matching: .images
            ) {
                Image(systemName: "plus")
                    .font(.system(size: 40, weight: .semibold))
                    .frame(width: 84, height: 84)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择图片")

            VStack(spacing: 6) {
                Text("选择图片")
                    .font(.headline)

                if showsAuthorizationCTA {
                    Button(AppLocalization.string("授权访问图库")) {
                        onRequestPhotoPermission?()
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(.top, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct ManualPhotoImportProgressOverlay: View {
    let title: String
    let fraction: Double?

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                if let fraction {
                    ProgressView(value: fraction)
                        .frame(width: 190)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(minWidth: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#endif
