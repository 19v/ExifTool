#if os(iOS)

import SwiftUI
import UIKit

struct PhotoDetailPlatformToolbar: ToolbarContent {
    @Binding var showsChineseKeys: Bool
    let photoNavigation: PhotoNavigationConfiguration?
    let isPreparingPhotoShare: Bool
    let canShareParameters: Bool
    let onSharePhoto: () -> Void
    let onShareParameters: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .platformLanguageToggle) {
            Button {
                showsChineseKeys.toggle()
            } label: {
                Label(showsChineseKeys ? "English" : "中文", systemImage: "translate")
            }
            .accessibilityLabel(showsChineseKeys ? "显示英文字段名" : "显示中文字段名")

            Spacer()

            if let photoNavigation {
                Button {
                    photoNavigation.selectPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!photoNavigation.canSelectPrevious)
                .accessibilityLabel("上一张照片")

                Button {
                    photoNavigation.selectNext()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!photoNavigation.canSelectNext)
                .accessibilityLabel("下一张照片")
            }

            Spacer()

            Button {
                guard let photosAppURL = URL(string: "photos-redirect://") else {
                    return
                }
                openURL(photosAppURL)
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
            }
            .accessibilityLabel("打开系统相册")
        }

        ToolbarItem(placement: .primaryAction) {
            PhotoDetailShareMenu(
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
        sheet(item: item) { shareItem in
            ActivityView(activityItems: shareItem.items)
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

#endif
