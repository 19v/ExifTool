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

            Menu {
                Button {
                    guard let photosAppURL = URL(string: "photos-redirect://") else {
                        return
                    }
                    openURL(photosAppURL)
                } label: {
                    Label("打开系统相册", systemImage: "photo.on.rectangle.angled")
                }

                Divider()

                Button { } label: {
                    Label("编辑（未上线）", systemImage: "pencil")
                }
                .disabled(true)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("照片操作")
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
            ActivityView(activityItems: shareItem.items, cleanupURL: shareItem.cleanupURL)
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let cleanupURL: URL?

    final class Coordinator {
        private let cleanupURL: URL?
        private var hasCleanedUp = false

        init(cleanupURL: URL?) {
            self.cleanupURL = cleanupURL
        }

        func cleanup() {
            guard !hasCleanedUp, let cleanupURL else {
                return
            }
            hasCleanedUp = true
            PhotoTemporaryFileStore.removeIfManaged(cleanupURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(cleanupURL: cleanupURL)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.cleanup()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }

    static func dismantleUIViewController(_ uiViewController: UIActivityViewController, coordinator: Coordinator) {
        coordinator.cleanup()
    }
}

#endif
