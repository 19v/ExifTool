#if os(macOS)

import SwiftUI

struct MacRootView: View {
    @State private var workspace: MacPhotoWorkspace
    @AppStorage("readOnlyMode") private var readOnlyMode = true

    init(initialFileURLs: [URL] = []) {
        _workspace = State(initialValue: MacPhotoWorkspace(initialFileURLs: initialFileURLs))
    }

    var body: some View {
        MacPhotoDropTabView(readOnlyMode: readOnlyMode)
        .environment(workspace)
        .focusedSceneValue(\.macPhotoWorkspace, workspace)
        .onOpenURL { url in
            guard url.isFileURL else {
                return
            }

            Task {
                _ = await workspace.importFiles(from: [url])
            }
        }
    }
}

#endif
