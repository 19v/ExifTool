//
//  ManualPhotoPickerContent.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

internal import PhotosUI
import SwiftUI

struct ManualPhotoPickerContent: View {
    @ObservedObject var picker: ManualPhotoPickerViewModel
    let readOnlyMode: Bool
    let emptyTitle: LocalizedStringKey
    let emptyDescription: LocalizedStringKey
    let onPhotoViewed: (() -> Void)?
    let onPhotoDetailVisibilityChanged: ((Bool) -> Void)?
    let showsLibraryAccessPrompt: Bool
    let onRequestLibraryAccess: (() -> Void)?

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedAssetForDetail: PhotoAsset?
    @State private var isShowingPhotoDetail = false

    init(
        picker: ManualPhotoPickerViewModel,
        readOnlyMode: Bool,
        emptyTitle: LocalizedStringKey = "选择图片",
        emptyDescription: LocalizedStringKey = "选中的图片只在当前会话中使用，不会修改系统照片库。",
        onPhotoViewed: (() -> Void)? = nil,
        onPhotoDetailVisibilityChanged: ((Bool) -> Void)? = nil,
        showsLibraryAccessPrompt: Bool = false,
        onRequestLibraryAccess: (() -> Void)? = nil
    ) {
        self.picker = picker
        self.readOnlyMode = readOnlyMode
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.onPhotoViewed = onPhotoViewed
        self.onPhotoDetailVisibilityChanged = onPhotoDetailVisibilityChanged
        self.showsLibraryAccessPrompt = showsLibraryAccessPrompt
        self.onRequestLibraryAccess = onRequestLibraryAccess
    }

    var body: some View {
        Group {
            if picker.assets.isEmpty {
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
                        Text(emptyTitle)
                            .font(.headline)
                        Text(emptyDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if showsLibraryAccessPrompt, let onRequestLibraryAccess {
                            Button("授权全部图库") {
                                onRequestLibraryAccess()
                            }
                            .buttonStyle(.plain)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.top, 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else {
                PhotoAssetGridView(
                    assets: picker.assets,
                    readOnlyMode: readOnlyMode,
                    onAssetOpen: handlePhotoDetailOpened,
                    onAssetClose: handlePhotoDetailClosed,
                    onRefresh: {
                        selectedItems = []
                    }
                )
                .safeAreaInset(edge: .bottom) {
                    if !isShowingPhotoDetail {
                        HStack {
                            PhotosPicker(
                                selection: $selectedItems,
                                maxSelectionCount: 1,
                                matching: .images
                            ) {
                                Label("重新选择", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)

                            if picker.isImporting {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .background(.bar)
                    }
                }
            }
        }
        .overlay {
            if picker.isImporting && picker.assets.isEmpty {
                ProgressView("正在读取图片")
            }
        }
        .task(id: selectedItems.map(\.hashValue)) {
            guard !selectedItems.isEmpty else {
                return
            }

            picker.clearError()
            let importedAssets = await picker.importPhotos(from: selectedItems)
            selectedItems = []

            if let importedAsset = importedAssets.first {
                selectedAssetForDetail = importedAsset
                picker.clearAssets()
            }
        }
        .navigationDestination(item: $selectedAssetForDetail) { asset in
            PhotoDetailView(
                assets: [asset],
                initialAssetID: asset.id,
                readOnlyMode: readOnlyMode
            )
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                handlePhotoDetailOpened()
            }
            .onDisappear {
                handlePhotoDetailClosed()
            }
        }
        .alert("导入失败", isPresented: errorBinding) {
            Button("知道了") {
                picker.clearError()
            }
        } message: {
            Text(picker.importErrorMessage ?? AppLocalization.string("manualPicker.importFailure"))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { picker.importErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    picker.clearError()
                }
            }
        )
    }

    private func handlePhotoDetailOpened() {
        isShowingPhotoDetail = true
        onPhotoDetailVisibilityChanged?(true)
        onPhotoViewed?()
    }

    private func handlePhotoDetailClosed() {
        isShowingPhotoDetail = false
        onPhotoDetailVisibilityChanged?(false)
    }
}

#endif
