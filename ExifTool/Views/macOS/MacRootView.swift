#if os(macOS)

import SwiftUI

struct MacRootView: View {
    @State private var workspace: MacPhotoWorkspace
    @State private var selectedTab = AppTab.photos
    @AppStorage("readOnlyMode") private var readOnlyMode = true

    init(initialFileURLs: [URL] = []) {
        _workspace = State(initialValue: MacPhotoWorkspace(initialFileURLs: initialFileURLs))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("照片", systemImage: "photo.on.rectangle", value: AppTab.photos) {
                MacPhotoDropTabView(readOnlyMode: readOnlyMode)
            }

            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                MacSettingsTabView(readOnlyMode: $readOnlyMode)
            }
        }
        .environment(workspace)
        .focusedSceneValue(\.macPhotoWorkspace, workspace)
        .onOpenURL { url in
            guard url.isFileURL else {
                return
            }

            _ = workspace.importFiles(from: [url])
        }
    }
}

#endif
