//
//  SettingsTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI
#if os(iOS)
import UIKit
internal import PhotosUI
#endif

struct SettingsTabView: View {
    @Binding var readOnlyMode: Bool
    @Binding var allowsICloudDownload: Bool
    @Binding var showsOnlyLocalPhotos: Bool
    #if os(iOS)
    let accessScope: PhotoLibraryViewModel.AccessScope
    let authorizationState: PhotoLibraryViewModel.AuthorizationState
    let localPhotosSummarySnapshot: LocalPhotosStatusSnapshot?
    let localPhotosSummaryDestination: AppTab?
    let onOpenLocalPhotosSummary: (() -> Void)?
    let onRequestPhotoPermission: (() -> Void)?
    let onPresentLimitedLibraryPicker: (() -> Void)?
    @Environment(\.openURL) private var openURL
    @State private var showsICloudDownloadExplanation = false
    #else
    init(
        readOnlyMode: Binding<Bool>,
        allowsICloudDownload: Binding<Bool>,
        showsOnlyLocalPhotos: Binding<Bool>
    ) {
        self._readOnlyMode = readOnlyMode
        self._allowsICloudDownload = allowsICloudDownload
        self._showsOnlyLocalPhotos = showsOnlyLocalPhotos
    }
    #endif

    #if os(iOS)
    init(
        readOnlyMode: Binding<Bool>,
        accessScope: PhotoLibraryViewModel.AccessScope,
        authorizationState: PhotoLibraryViewModel.AuthorizationState,
        localPhotosSummarySnapshot: LocalPhotosStatusSnapshot?,
        localPhotosSummaryDestination: AppTab?,
        onOpenLocalPhotosSummary: (() -> Void)? = nil,
        onRequestPhotoPermission: (() -> Void)? = nil,
        onPresentLimitedLibraryPicker: (() -> Void)? = nil,
        allowsICloudDownload: Binding<Bool>,
        showsOnlyLocalPhotos: Binding<Bool>
    ) {
        self._readOnlyMode = readOnlyMode
        self.accessScope = accessScope
        self.authorizationState = authorizationState
        self.localPhotosSummarySnapshot = localPhotosSummarySnapshot
        self.localPhotosSummaryDestination = localPhotosSummaryDestination
        self.onOpenLocalPhotosSummary = onOpenLocalPhotosSummary
        self.onRequestPhotoPermission = onRequestPhotoPermission
        self.onPresentLimitedLibraryPicker = onPresentLimitedLibraryPicker
        self._allowsICloudDownload = allowsICloudDownload
        self._showsOnlyLocalPhotos = showsOnlyLocalPhotos
    }
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("安全"),
                    footer: Text("开启后，应用只读取照片和 Exif，不会修改照片或写入元数据。")
                ) {
                    Toggle("只读模式", isOn: $readOnlyMode)
                }

                Section(
                    header: Text("iCloud 照片"),
                    footer: Text("部分照片开启 iCloud 照片后只保存在云端。关闭联网下载时，应用不会主动联网；如果只想离线查看，可以打开“仅显示已下载到本地的照片”，先去系统相册下载好再回来。")
                ) {
                    Toggle("允许联网下载 iCloud 原图", isOn: iCloudDownloadBinding)
                    Toggle("仅显示已下载到本地的照片", isOn: $showsOnlyLocalPhotos)

                    #if os(iOS)
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
                    #endif
                }

                #if os(iOS)
                Section(
                    header: Text("相册权限"),
                    footer: Text(photoPermissionDescription)
                ) {
                    Button(photoPermissionActionTitle) {
                        handlePhotoPermissionAction()
                    }

                    if shouldShowLimitedEmptyReselectionAction {
                        Button("重新选择可访问照片") {
                            onPresentLimitedLibraryPicker?()
                        }
                    }
                }
                #endif

                #if os(iOS)
                Section {
                    Button("打开 App 系统设置") {
                        openAppSettings()
                    }
                }
                #endif
            }
            .navigationTitle("设置")
            #if os(iOS)
            .alert("允许联网下载 iCloud 原图？", isPresented: $showsICloudDownloadExplanation) {
                Button("保持离线", role: .cancel) { }
                Button("允许下载") {
                    allowsICloudDownload = true
                }
            } message: {
                Text("有些照片的原图和 Exif 只存在 iCloud，应用需要短暂联网把原图下载到本机后才能读取。你也可以继续保持离线，只查看已经在本地的照片。")
            }
            #endif
        }
    }

    #if os(iOS)
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
        switch localPhotosSummaryDestination {
        case .albums:
            return "rectangle.stack"
        case .photos:
            return "photo.on.rectangle.angled"
        case .search:
            return "magnifyingglass"
        case .settings, .picker, .none:
            return "arrow.up.forward"
        }
    }

    private var summaryDestinationAccessibilityHint: String {
        switch localPhotosSummaryDestination {
        case .albums:
            return AppLocalization.string("settings.localPhotosSummaryHint.albums")
        case .photos:
            return AppLocalization.string("settings.localPhotosSummaryHint.photos")
        case .search:
            return AppLocalization.string("settings.localPhotosSummaryHint.search")
        case .settings, .picker, .none:
            return AppLocalization.string("settings.localPhotosSummaryHint.default")
        }
    }

    private var photoPermissionActionTitle: String {
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

    private var photoPermissionDescription: String {
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

    private func handlePhotoPermissionAction() {
        if authorizationState == .unknown {
            onRequestPhotoPermission?()
            return
        }

        openAppSettings()
    }

    private var shouldShowLimitedEmptyReselectionAction: Bool {
        accessScope == .limited
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        openURL(settingsURL)
    }
    #else
    private var iCloudDownloadBinding: Binding<Bool> {
        $allowsICloudDownload
    }
    #endif
}
