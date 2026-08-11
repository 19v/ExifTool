#if os(macOS)

import SwiftUI

struct MacPhotoDetailPlatformToolbar: ToolbarContent {
    @Binding var showsChineseKeys: Bool
    let isPreparingPhotoShare: Bool
    let canShareParameters: Bool
    let onSharePhoto: () -> Void
    let onShareParameters: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .platformLanguageToggle) {
            Button {
                showsChineseKeys.toggle()
            } label: {
                Label(showsChineseKeys ? "English" : "中文", systemImage: "translate")
            }
            .accessibilityLabel(showsChineseKeys ? "显示英文字段名" : "显示中文字段名")
        }

        ToolbarItem(placement: .primaryAction) {
            MacPhotoDetailShareMenu(
                isPreparingPhotoShare: isPreparingPhotoShare,
                canShareParameters: canShareParameters,
                onSharePhoto: onSharePhoto,
                onShareParameters: onShareParameters
            )
        }
    }
}

extension View {
    func photoDetailActivityShareSheet(item: Binding<ActivityShareItem?>) -> some View {
        self
    }
}

#endif
