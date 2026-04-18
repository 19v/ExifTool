//
//  PlatformSettingsImportSource+iOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

import SwiftUI

struct PlatformSettingsImportSource: View {
    var body: some View {
        LabeledContent("导入") {
            Text("系统照片库或手动选图")
        }
    }
}

#endif
