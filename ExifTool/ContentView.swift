//
//  ContentView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI
#if os(iOS)
import Photos
internal import PhotosUI
import UIKit
#endif

struct ContentView: View {
    @StateObject private var library = PhotoLibraryViewModel()
    @State private var selectedTab = AppTab.picker
    @AppStorage("readOnlyMode") private var readOnlyMode = true
    @AppStorage("allowsICloudDownload") private var allowsICloudDownload = false
    @AppStorage("showsOnlyLocalPhotos") private var showsOnlyLocalPhotos = false
    @Environment(\.scenePhase) private var scenePhase
#if os(iOS)
    @StateObject private var manualPicker = ManualPhotoPickerViewModel()
    @State private var sharedPhotoAsset: PhotoAsset?
#endif
#if os(macOS)
    @StateObject private var macWorkspace = MacPhotoWorkspace()
#endif
    
#if os(macOS)
    init(initialFileURLs: [URL] = []) {
        _macWorkspace = StateObject(wrappedValue: MacPhotoWorkspace(initialFileURLs: initialFileURLs))
    }
#endif
    
    var body: some View {
        mainTabs
#if os(macOS)
            .environmentObject(macWorkspace)
            .focusedSceneValue(\.macPhotoWorkspace, macWorkspace)
            .onOpenURL { url in
                guard url.isFileURL else {
                    return
                }
                
                _ = macWorkspace.importFiles(from: [url])
            }
#endif
#if !os(macOS)
            .task {
                await library.prepare(showingOnlyLocalAssets: showsOnlyLocalPhotos)
            }
            .onOpenURL { url in
                openIncomingPhoto(from: url)
            }
            .sheet(item: $sharedPhotoAsset) { asset in
                NavigationStack {
                    PhotoDetailView(
                        assets: manualPicker.assets.isEmpty ? [asset] : manualPicker.assets,
                        initialAssetID: asset.id,
                        readOnlyMode: readOnlyMode
                    )
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
                
                Task {
                    await library.refresh()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showsLimitedLibraryButton {
                    limitedLibraryButton
                }
            }
#endif
    }
    
    @ViewBuilder
    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
#if os(macOS)
            Tab("照片", systemImage: "photo.on.rectangle", value: AppTab.photos) {
                MacPhotoDropTabView(readOnlyMode: readOnlyMode)
            }
            
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                SettingsTabView(
                    readOnlyMode: $readOnlyMode,
                    allowsICloudDownload: $allowsICloudDownload,
                    showsOnlyLocalPhotos: $showsOnlyLocalPhotos
                )
            }
#else
            if showsLibraryTabs {
                Tab("图库", systemImage: "photo.on.rectangle.angled", value: AppTab.photos) {
                    PhotoPickerTabView(
                        library: library,
                        manualPicker: manualPicker,
                        readOnlyMode: readOnlyMode
                    )
                }
                
                Tab("相册", systemImage: "rectangle.stack", value: AppTab.albums) {
                    AlbumsTabView(library: library, readOnlyMode: readOnlyMode)
                }
                
                Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsTabView(
                        readOnlyMode: $readOnlyMode,
                        authorizationState: library.authorizationState,
                        localPhotosSummarySnapshot: library.localPhotosSummarySnapshot,
                        localPhotosSummaryDestination: localPhotosSummaryDestination,
                        onOpenLocalPhotosSummary: openLocalPhotosSummary,
                        allowsICloudDownload: $allowsICloudDownload,
                        showsOnlyLocalPhotos: $showsOnlyLocalPhotos
                    )
                }
                
                Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                    SearchTabView(library: library, readOnlyMode: readOnlyMode)
                }
            } else {
                Tab("选图", systemImage: "plus.square.on.square", value: AppTab.picker) {
                    ManualPhotoPickerTabView(picker: manualPicker, readOnlyMode: readOnlyMode)
                }
                
                Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsTabView(
                        readOnlyMode: $readOnlyMode,
                        authorizationState: library.authorizationState,
                        localPhotosSummarySnapshot: library.localPhotosSummarySnapshot,
                        localPhotosSummaryDestination: localPhotosSummaryDestination,
                        onOpenLocalPhotosSummary: openLocalPhotosSummary,
                        allowsICloudDownload: $allowsICloudDownload,
                        showsOnlyLocalPhotos: $showsOnlyLocalPhotos
                    )
                }
            }
#endif
        }
    }
    
#if os(iOS)
    private var showsLibraryTabs: Bool {
        switch library.accessScope {
        case .full, .limited:
            return true
        case .unknown, .denied:
            return false
        }
    }
    
    private var showsLimitedLibraryButton: Bool {
        library.accessScope == .limited
    }
    
    private var limitedLibraryButton: some View {
        HStack {
            Spacer()
            
            Button("重新选择照片") {
                presentLimitedLibraryPicker()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 58)
    }
    
    private func syncSelectedTab() {
        if showsLibraryTabs {
            if selectedTab == .picker {
                selectedTab = .photos
            }
        } else if selectedTab != .picker && selectedTab != .settings {
            selectedTab = .picker
        }
    }
    
    private func presentLimitedLibraryPicker() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootViewController = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }
        
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: topViewController(for: rootViewController))
    }
    
    private func topViewController(for rootViewController: UIViewController) -> UIViewController {
        var topViewController = rootViewController
        
        while let presentedViewController = topViewController.presentedViewController {
            topViewController = presentedViewController
        }
        
        return topViewController
    }

    private var localPhotosSummaryDestination: AppTab? {
        guard showsOnlyLocalPhotos else {
            return nil
        }

        if library.isBuildingLocalAlbumStats {
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
            return
        }

        openSharedPhoto(from: url)
    }

    private func openDocumentPhoto(from url: URL) {
        let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let asset = manualPicker.importSharedPhoto(from: url) else {
            manualPicker.importErrorMessage = "无法打开分享的照片，请重新从相册分享一次。"
            selectedTab = .picker
            return
        }

        selectedTab = .picker
        sharedPhotoAsset = asset
    }

    private func openSharedPhoto(from url: URL) {
        guard let fileName = SharedPhotoImport.fileName(from: url),
              let fileURL = SharedPhotoImport.fileURL(forSharedFileName: fileName),
              let asset = manualPicker.importSharedPhoto(from: fileURL) else {
            manualPicker.importErrorMessage = "无法打开分享的照片，请重新从相册分享一次。"
            selectedTab = .picker
            return
        }

        selectedTab = .picker
        sharedPhotoAsset = asset
    }
#endif
}
