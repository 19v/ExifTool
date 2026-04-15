//
//  ContentView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var library = PhotoLibraryViewModel()
    @State private var selectedTab = AppTab.photos
    @AppStorage("readOnlyMode") private var readOnlyMode = true
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
            await library.prepare()
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
                SettingsTabView(readOnlyMode: $readOnlyMode)
            }
        #else
            Tab("照片", systemImage: "photo.on.rectangle", value: AppTab.photos) {
                PhotoPickerTabView(library: library, readOnlyMode: readOnlyMode)
            }

            Tab("相册", systemImage: "rectangle.stack", value: AppTab.albums) {
                AlbumsTabView(library: library, readOnlyMode: readOnlyMode)
            }

            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                SettingsTabView(readOnlyMode: $readOnlyMode)
            }

            Tab("搜索", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchTabView(library: library, readOnlyMode: readOnlyMode)
            }
        #endif
        }
    }
}
