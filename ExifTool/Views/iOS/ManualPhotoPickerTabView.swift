#if os(iOS)

internal import PhotosUI
import SwiftUI

struct ManualPhotoPickerTabView: View {
    let readOnlyMode: Bool
    let authorizationState: PhotoLibraryViewModel.AuthorizationState
    let onRequestPhotoPermission: (() -> Void)?

    @AppStorage("hasShownInitialPhotoLibraryAuthorizationCTA")
    private var hasShownInitialPhotoLibraryAuthorizationCTA = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedAssetForDetail: PhotoAsset?
    @State private var showsImportingDialog = false
    @State private var importProgressTitle = AppLocalization.string("manualPicker.readingImage")
    @State private var importProgressFraction: Double?
    @State private var importErrorMessage: String?
    @State private var showsInitialAuthorizationCTAThisSession = false

    var body: some View {
        NavigationStack {
            emptyState
                .navigationTitle("选图")
        }
        .sheet(item: $selectedAssetForDetail) { asset in
            NavigationStack {
                PhotoDetailView(
                    assets: [asset],
                    initialAssetID: asset.id,
                    readOnlyMode: readOnlyMode
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if showsImportingDialog {
                importingDialog
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

    private var emptyState: some View {
        VStack(spacing: 18) {
            pickerButton()

            VStack(spacing: 6) {
                Text("选择图片")
                    .font(.headline)
                Text("选中的图片只在当前会话中使用，不会修改系统照片库。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if shouldShowInitialAuthorizationCTA {
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
        .onAppear {
            guard authorizationState == .unknown else {
                showsInitialAuthorizationCTAThisSession = false
                return
            }

            if !hasShownInitialPhotoLibraryAuthorizationCTA {
                showsInitialAuthorizationCTAThisSession = true
                hasShownInitialPhotoLibraryAuthorizationCTA = true
            }
        }
        .onChange(of: authorizationState) { _, newValue in
            if newValue != .unknown {
                showsInitialAuthorizationCTAThisSession = false
            }
        }
    }

    private func pickerButton() -> some View {
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

    private var importingDialog: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                if let importProgressFraction {
                    ProgressView(value: importProgressFraction)
                        .frame(width: 190)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
                Text(importProgressTitle)
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
            selectedAssetForDetail = firstAsset
        } else if importErrorMessage == nil {
            importErrorMessage = AppLocalization.string("manualPicker.noReadableImages")
        }
    }
}

#endif
