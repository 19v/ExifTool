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
    let authorizationState: PhotoLibraryViewModel.AuthorizationState
    let localPhotosSummarySnapshot: LocalPhotosStatusSnapshot?
    let localPhotosSummaryDestination: AppTab?
    let onOpenLocalPhotosSummary: (() -> Void)?
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
        authorizationState: PhotoLibraryViewModel.AuthorizationState,
        localPhotosSummarySnapshot: LocalPhotosStatusSnapshot?,
        localPhotosSummaryDestination: AppTab?,
        onOpenLocalPhotosSummary: (() -> Void)? = nil,
        allowsICloudDownload: Binding<Bool>,
        showsOnlyLocalPhotos: Binding<Bool>
    ) {
        self._readOnlyMode = readOnlyMode
        self.authorizationState = authorizationState
        self.localPhotosSummarySnapshot = localPhotosSummarySnapshot
        self.localPhotosSummaryDestination = localPhotosSummaryDestination
        self.onOpenLocalPhotosSummary = onOpenLocalPhotosSummary
        self._allowsICloudDownload = allowsICloudDownload
        self._showsOnlyLocalPhotos = showsOnlyLocalPhotos
    }
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("安全") {
                    Toggle("只读模式", isOn: $readOnlyMode)
                    Text("开启后，应用只读取照片和 Exif，不会修改照片或写入元数据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                if showsSettingsShortcut {
                    Section("相册权限") {
                        Button(photoPermissionActionTitle) {
                            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }

                            openURL(settingsURL)
                        }

                        Text(photoPermissionDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif

                Section("应用") {
                    LabeledContent("名称", value: "ExifTool")
                    PlatformSettingsImportSource()
                }
            }
            .navigationTitle("设置")
            .platformInlineNavigationTitle()
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
    private var showsSettingsShortcut: Bool {
        authorizationState != .unknown
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
            return "打开相册页面查看本地照片统计"
        case .photos:
            return "打开图库页面继续加载本地照片"
        case .search:
            return "打开搜索页面查看本地照片"
        case .settings, .picker, .none:
            return "打开相关页面查看本地照片状态"
        }
    }

    private var photoPermissionActionTitle: String {
        switch authorizationState {
        case .authorized:
            return "前往系统设置管理全部图库权限"
        case .limited:
            return "前往系统设置管理部分图片权限"
        case .denied:
            return "前往系统设置重新开启相册权限"
        case .empty:
            return "前往系统设置检查相册权限"
        case .unknown:
            return "前往系统设置"
        }
    }

    private var photoPermissionDescription: String {
        switch authorizationState {
        case .authorized:
            return "当前已允许访问整个图库。如果想改成部分图片，或直接关闭权限，可以前往系统设置调整。"
        case .limited:
            return "当前只允许访问部分图片。如果想扩大到整个图库、重新挑选照片，或直接关闭权限，可以前往系统设置调整。"
        case .denied:
            return "当前未允许访问系统照片库。如果想重新开启权限，可以前往系统设置调整。"
        case .empty:
            return "当前权限下没有可用照片。如果想检查是否改成了部分图片权限，或直接关闭权限，可以前往系统设置调整。"
        case .unknown:
            return "可以前往系统设置查看当前的相册权限。"
        }
    }
    #else
    private var iCloudDownloadBinding: Binding<Bool> {
        $allowsICloudDownload
    }
    #endif
}
