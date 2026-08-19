#if os(macOS)

import SwiftUI

struct MacPhotoDetailShareMenu: View {
    let isPreparingPhotoShare: Bool
    let canShareParameters: Bool
    let onSharePhoto: () -> Void
    let onShareParameters: () -> Void

    var body: some View {
        Menu {
            Button(action: onSharePhoto) {
                Label(isPreparingPhotoShare ? "正在准备照片" : "分享照片", systemImage: "photo")
            }
            .disabled(isPreparingPhotoShare)

            Button(action: onShareParameters) {
                Label("分享参数", systemImage: "list.bullet.rectangle")
            }
            .disabled(!canShareParameters)
        } label: {
            if isPreparingPhotoShare {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .accessibilityLabel("分享")
    }
}

#endif
