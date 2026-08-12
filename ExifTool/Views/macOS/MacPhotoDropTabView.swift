//
//  MacPhotoDropTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import SwiftUI
import UniformTypeIdentifiers

struct MacPhotoDropTabView: View {
    let readOnlyMode: Bool

    @Environment(MacPhotoWorkspace.self) private var workspace
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false
    @State private var isImporterPresented = false
    @State private var isCompareModeEnabled = false
    @State private var compareAssetID: String?

    var body: some View {
        @Bindable var workspace = workspace

        NavigationStack {
            Group {
                if workspace.sortedAssets.isEmpty {
                    MacPhotoDropPlaceholder(
                        isDropTargeted: isDropTargeted,
                        recentFiles: workspace.recentFiles,
                        onPickFiles: { isImporterPresented = true },
                        onOpenRecentFile: { url in
                            Task {
                                _ = await workspace.openRecentFile(url)
                            }
                        },
                        onClearRecentFiles: {
                            workspace.clearRecentFiles()
                        }
                    )
                } else {
                    NavigationSplitView {
                        MacDroppedPhotoSidebar(
                            assets: workspace.sortedAssets,
                            selectedAssetID: $workspace.selectedAssetID
                        )
                    } detail: {
                        if let selectedAsset = selectedAsset {
                            if isCompareModeEnabled, workspace.sortedAssets.count > 1 {
                                MacPhotoCompareDetailView(
                                    assets: workspace.sortedAssets,
                                    primaryAsset: selectedAsset,
                                    compareAssetID: $compareAssetID,
                                    readOnlyMode: readOnlyMode
                                )
                            } else {
                                MacPhotoDetailView(
                                    asset: selectedAsset,
                                    readOnlyMode: readOnlyMode
                                )
                                .id(selectedAsset.id)
                            }
                        } else {
                            ContentUnavailableView("没有选中的照片", systemImage: "photo")
                        }
                    }
                }
            }
            .navigationTitle(workspace.windowTitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("选择文件") {
                        workspace.pickFiles()
                    }

                    if !workspace.sortedAssets.isEmpty {
                        Button {
                            workspace.selectPreviousAsset()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .help("上一张")
                        .disabled(!workspace.canSelectPreviousAsset)

                        Button {
                            workspace.selectNextAsset()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .help("下一张")
                        .disabled(!workspace.canSelectNextAsset)
                    }

                    if workspace.sortedAssets.count > 1 {
                        Button(isCompareModeEnabled ? "关闭对比" : "对比") {
                            isCompareModeEnabled.toggle()
                            ensureCompareSelection()
                        }
                        .help(isCompareModeEnabled ? "关闭对比模式" : "左右对比两张照片")
                    }

                    if !workspace.recentFiles.isEmpty {
                        Menu("最近打开") {
                            ForEach(workspace.recentFiles, id: \.self) { url in
                                Button(url.lastPathComponent) {
                                    Task {
                                        _ = await workspace.openRecentFile(url)
                                    }
                                }
                            }

                            Divider()

                            Button("清除最近记录") {
                                workspace.clearRecentFiles()
                            }
                        }
                    }

                    if !workspace.sortedAssets.isEmpty {
                        if workspace.hasCurrentFile {
                            Button("新窗口打开") {
                                guard let filePath = workspace.currentFilePath else {
                                    return
                                }

                                openWindow(id: macPhotoViewerWindowID, value: filePath)
                            }

                            Button("复制路径") {
                                workspace.copyCurrentFilePath()
                            }

                            Button("默认应用打开") {
                                workspace.openCurrentFileInDefaultApp()
                            }

                            Button("在 Finder 中显示") {
                                workspace.revealCurrentFileInFinder()
                            }
                        }

                        Menu("排序") {
                            Picker("排序", selection: $workspace.sortMode) {
                                ForEach(MacPhotoWorkspace.SortMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                        }

                        Button("清空") {
                            workspace.clear()
                        }
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else {
                return false
            }
            Task {
                _ = await workspace.importFiles(from: urls)
            }
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                return
            }

            Task {
                _ = await workspace.importFiles(from: urls)
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                workspace.selectPreviousAsset()
            case .right:
                workspace.selectNextAsset()
            default:
                break
            }
        }
        .onAppear {
            ensureCompareSelection()
        }
        .onChange(of: workspace.selectedAssetID) { _, _ in
            ensureCompareSelection()
        }
        .onChange(of: workspace.sortedAssets.map(\.id)) { _, _ in
            ensureCompareSelection()
        }
    }

    private var selectedAsset: PhotoAsset? {
        guard let selectedAssetID = workspace.selectedAssetID else {
            return workspace.sortedAssets.first
        }

        return workspace.sortedAssets.first(where: { $0.id == selectedAssetID })
    }

    private func ensureCompareSelection() {
        let assetIDs = Set(workspace.sortedAssets.map(\.id))
        if let compareAssetID, !assetIDs.contains(compareAssetID) {
            self.compareAssetID = nil
        }

        guard let selectedAsset else {
            compareAssetID = nil
            isCompareModeEnabled = false
            return
        }

        if compareAssetID == selectedAsset.id {
            compareAssetID = nil
        }

        if isCompareModeEnabled && compareAssetID == nil {
            compareAssetID = workspace.sortedAssets.first(where: { $0.id != selectedAsset.id })?.id
        }

        if workspace.sortedAssets.count < 2 {
            isCompareModeEnabled = false
            compareAssetID = nil
        }
    }
}

#endif
