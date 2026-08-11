#if os(macOS)

//
//  SettingsTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct MacReadOnlySettingsSection: View {
    @Binding var readOnlyMode: Bool

    var body: some View {
        Section(
            header: Text("安全"),
            footer: Text("开启后，应用只读取照片和 Exif，不会修改照片或写入元数据。")
        ) {
            Toggle("只读模式", isOn: $readOnlyMode)
        }
    }
}

struct MacAppVersionSettingsSection: View {
    var body: some View {
        Section {
            EmptyView()
        } footer: {
            Text(appVersionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel(appVersionAccessibilityLabel)
        }
    }

    private var appVersionText: String {
        if let versionNumber, let buildNumber {
            return "版本 \(versionNumber) (Build \(buildNumber))"
        }

        if let versionNumber {
            return "版本 \(versionNumber)"
        }

        if let buildNumber {
            return "Build \(buildNumber)"
        }

        return "版本未知"
    }

    private var appVersionAccessibilityLabel: String {
        if let versionNumber, let buildNumber {
            return "当前版本 \(versionNumber)，Build \(buildNumber)"
        }

        return appVersionText
    }

    private var versionNumber: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private var buildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}

#endif


