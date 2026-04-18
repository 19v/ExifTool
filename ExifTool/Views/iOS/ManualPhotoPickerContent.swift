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

    @State private var selectedItems: [PhotosPickerItem] = []

    init(
        picker: ManualPhotoPickerViewModel,
        readOnlyMode: Bool,
        emptyTitle: LocalizedStringKey = "选择图片",
        emptyDescription: LocalizedStringKey = "支持多选。选中的图片只在当前会话中使用，不会修改系统照片库。"
    ) {
        self.picker = picker
        self.readOnlyMode = readOnlyMode
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
    }

    var body: some View {
        Group {
            if picker.assets.isEmpty {
                VStack(spacing: 18) {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: nil,
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
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else {
                PhotoAssetGridView(assets: picker.assets, readOnlyMode: readOnlyMode, onRefresh: {
                    selectedItems = []
                })
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: nil,
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
            await picker.importPhotos(from: selectedItems)
            selectedItems = []
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
}

#endif
