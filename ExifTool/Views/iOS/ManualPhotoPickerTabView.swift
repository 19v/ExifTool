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
    @State private var isImporting = false
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
            if isImporting {
                ProgressView("正在读取图片")
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

    private func importSelectedItems() async {
        guard !selectedItems.isEmpty else {
            return
        }

        isImporting = true
        defer {
            isImporting = false
            selectedItems = []
        }

        importErrorMessage = nil
        var assets: [PhotoAsset] = []
        assets.reserveCapacity(selectedItems.count)

        for (index, item) in selectedItems.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let baseFileName = "\(AppLocalization.string("photoFileImporter.pickedImage")) \(index + 1)"
                let suggestedFileName = item.supportedContentTypes.first?.preferredFilenameExtension.map {
                    "\(baseFileName).\($0)"
                } ?? baseFileName

                if let asset = PhotoFileImporter.importAsset(
                    from: data,
                    suggestedFileName: suggestedFileName,
                    id: item.itemIdentifier ?? UUID().uuidString
                ) {
                    assets.append(asset)
                }
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
