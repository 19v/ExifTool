//
//  PhotoViews+iOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

internal import PhotosUI
import SwiftUI
import UIKit

extension Color {
    static var platformSecondaryBackground: Color {
        Color(.secondarySystemBackground)
    }
}

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    func platformDetailPagingStyle() -> some View {
        tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    @ViewBuilder
    func platformTabBarHidden() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

extension ToolbarItemPlacement {
    static var platformLanguageToggle: ToolbarItemPlacement {
        .topBarTrailing
    }
}

struct PlatformAlbumList: View {
    let albums: [PhotoAlbum]
    let readOnlyMode: Bool
    let onRefresh: (() async -> Void)?

    init(albums: [PhotoAlbum], readOnlyMode: Bool, onRefresh: (() async -> Void)? = nil) {
        self.albums = albums
        self.readOnlyMode = readOnlyMode
        self.onRefresh = onRefresh
    }

    var body: some View {
        List(albums) { album in
            NavigationLink {
                AlbumDetailView(album: album, readOnlyMode: readOnlyMode)
            } label: {
                AlbumRowView(album: album)
            }
        }
        .refreshable {
            await onRefresh?()
        }
        .listStyle(.insetGrouped)
    }
}

struct ManualPhotoPickerTabView: View {
    @ObservedObject var picker: ManualPhotoPickerViewModel
    let readOnlyMode: Bool

    var body: some View {
        NavigationStack {
            ManualPhotoPickerContent(picker: picker, readOnlyMode: readOnlyMode)
                .navigationTitle("选图")
                .platformInlineNavigationTitle()
        }
    }
}

struct ManualPhotoPickerAccessView: View {
    @ObservedObject var picker: ManualPhotoPickerViewModel
    let readOnlyMode: Bool

    var body: some View {
        ManualPhotoPickerContent(
            picker: picker,
            readOnlyMode: readOnlyMode,
            emptyTitle: "未授权系统照片库",
            emptyDescription: "可以直接点加号手动选择图片，多选后照样查看 Exif。"
        )
    }
}

private struct ManualPhotoPickerContent: View {
    @ObservedObject var picker: ManualPhotoPickerViewModel
    let readOnlyMode: Bool
    let emptyTitle: String
    let emptyDescription: String

    @State private var selectedItems: [PhotosPickerItem] = []

    init(
        picker: ManualPhotoPickerViewModel,
        readOnlyMode: Bool,
        emptyTitle: String = "选择图片",
        emptyDescription: String = "支持多选。选中的图片只在当前会话中使用，不会修改系统照片库。"
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
                PhotoAssetGridView(assets: picker.assets, readOnlyMode: readOnlyMode) {
                    selectedItems = []
                }
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
            Text(picker.importErrorMessage ?? "没有成功导入图片。")
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

struct PlatformSettingsImportSource: View {
    var body: some View {
        LabeledContent("导入", value: "系统照片库或手动选图")
    }
}

struct PlatformPhotoGridScrollScrubber: View {
    var body: some View {
        EmptyView()
    }
}

#endif
