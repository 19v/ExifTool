#if os(iOS)

internal import PhotosUI
import SwiftUI
import UIKit

struct IOSSettingsTabView: View {
    let accessScope: PhotoLibraryViewModel.AccessScope
    let authorizationState: PhotoLibraryViewModel.AuthorizationState
    let localPhotosSummarySnapshot: LocalPhotosStatusSnapshot?
    let onOpenLocalPhotosSummary: (() -> Void)?
    let onRequestPhotoPermission: (() -> Void)?
    let onPresentLimitedLibraryPicker: (() -> Void)?
    @Binding var allowsICloudDownload: Bool
    @Binding var showsOnlyLocalPhotos: Bool

    @Environment(\.openURL) private var openURL
    @State private var showsICloudDownloadExplanation = false

    var body: some View {
        NavigationStack {
            Form {
                IOSICloudSettingsSection(
                    allowsICloudDownload: iCloudDownloadBinding,
                    showsOnlyLocalPhotos: $showsOnlyLocalPhotos,
                    localPhotosSummarySnapshot: localPhotosSummarySnapshot,
                    summaryDestinationIconName: summaryDestinationIconName,
                    summaryDestinationAccessibilityHint: summaryDestinationAccessibilityHint,
                    onOpenLocalPhotosSummary: onOpenLocalPhotosSummary
                )
                IOSPhotoPermissionSettingsSection(
                    authorizationState: authorizationState,
                    showsLimitedLibraryAction: accessScope == .limited,
                    onPrimaryAction: handlePhotoPermissionAction,
                    onPresentLimitedLibraryPicker: onPresentLimitedLibraryPicker
                )

                Section {
                    Button("打开 App 系统设置") {
                        openAppSettings()
                    }
                }

                AppVersionSettingsSection()
            }
            .navigationTitle("设置")
            .alert("允许联网下载 iCloud 原图？", isPresented: $showsICloudDownloadExplanation) {
                Button("保持离线", role: .cancel) { }
                Button("允许下载") {
                    allowsICloudDownload = true
                }
            } message: {
                Text("有些照片的原图和 Exif 只存在 iCloud，应用需要短暂联网把原图下载到本机后才能读取。你也可以继续保持离线，只查看已经在本地的照片。")
            }
        }
    }

    private var iCloudDownloadBinding: Binding<Bool> {
        Binding(
            get: { allowsICloudDownload },
            set: { newValue in
                if newValue {
                    showsICloudDownloadExplanation = true
                } else {
                    allowsICloudDownload = false
                }
            }
        )
    }

    private var summaryDestinationIconName: String {
        onOpenLocalPhotosSummary == nil ? "arrow.up.forward" : "photo.on.rectangle.angled"
    }

    private var summaryDestinationAccessibilityHint: String {
        onOpenLocalPhotosSummary == nil
            ? AppLocalization.string("settings.localPhotosSummaryHint.default")
            : AppLocalization.string("settings.localPhotosSummaryHint.photos")
    }

    private func handlePhotoPermissionAction() {
        if authorizationState == .unknown {
            onRequestPhotoPermission?()
        } else {
            openAppSettings()
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        openURL(settingsURL)
    }
}

private struct IOSICloudSettingsSection: View {
    @Binding var allowsICloudDownload: Bool
    @Binding var showsOnlyLocalPhotos: Bool
    let localPhotosSummarySnapshot: LocalPhotosStatusSnapshot?
    let summaryDestinationIconName: String
    let summaryDestinationAccessibilityHint: String
    let onOpenLocalPhotosSummary: (() -> Void)?

    var body: some View {
        Section(
            header: Text("iCloud 照片"),
            footer: Text("部分照片开启 iCloud 照片后只保存在云端。关闭联网下载时，应用不会主动联网；如果只想离线查看，可以打开“仅显示已下载到本地的照片”，先去系统相册下载好再回来。")
        ) {
            Toggle("允许联网下载 iCloud 原图", isOn: $allowsICloudDownload)
            Toggle("仅显示已下载到本地的照片", isOn: $showsOnlyLocalPhotos)

            if showsOnlyLocalPhotos, let localPhotosSummarySnapshot {
                if let onOpenLocalPhotosSummary {
                    LocalPhotosSummaryButton(
                        snapshot: localPhotosSummarySnapshot,
                        iconName: summaryDestinationIconName,
                        accessibilityHint: summaryDestinationAccessibilityHint,
                        action: onOpenLocalPhotosSummary
                    )
                } else {
                    Text(localPhotosSummarySnapshot.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct IOSPhotoPermissionSettingsSection: View {
    let authorizationState: PhotoLibraryViewModel.AuthorizationState
    let showsLimitedLibraryAction: Bool
    let onPrimaryAction: () -> Void
    let onPresentLimitedLibraryPicker: (() -> Void)?

    var body: some View {
        Section(
            header: Text("相册权限"),
            footer: Text(permissionDescription)
        ) {
            Button(permissionActionTitle, action: onPrimaryAction)

            if showsLimitedLibraryAction {
                Button("重新选择可访问照片") {
                    onPresentLimitedLibraryPicker?()
                }
            }
        }
    }

    private var permissionActionTitle: String {
        switch authorizationState {
        case .authorized:
            return AppLocalization.string("settings.photoPermissionAction.authorized")
        case .limited:
            return AppLocalization.string("settings.photoPermissionAction.limited")
        case .denied:
            return AppLocalization.string("settings.photoPermissionAction.denied")
        case .empty:
            return AppLocalization.string("settings.photoPermissionAction.empty")
        case .unknown:
            return AppLocalization.string("授权访问图库")
        }
    }

    private var permissionDescription: String {
        switch authorizationState {
        case .authorized:
            return AppLocalization.string("settings.photoPermissionDescription.authorized")
        case .limited:
            return AppLocalization.string("settings.photoPermissionDescription.limited")
        case .denied:
            return AppLocalization.string("settings.photoPermissionDescription.denied")
        case .empty:
            return AppLocalization.string("settings.photoPermissionDescription.empty")
        case .unknown:
            return AppLocalization.string("settings.photoPermissionDescription.unknown")
        }
    }
}

#endif
