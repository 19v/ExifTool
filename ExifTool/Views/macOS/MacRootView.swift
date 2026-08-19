#if os(macOS)

import SwiftUI

struct MacRootView: View {
    @State private var workspace: MacPhotoWorkspace

    init(initialFileURLs: [URL] = []) {
        _workspace = State(initialValue: MacPhotoWorkspace(initialFileURLs: initialFileURLs))
    }

    var body: some View {
        MacPhotoDropTabView()
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
