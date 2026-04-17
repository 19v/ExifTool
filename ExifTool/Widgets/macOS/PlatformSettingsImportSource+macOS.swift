//
//  PlatformSettingsImportSource+macOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import SwiftUI

struct PlatformSettingsImportSource: View {
    var body: some View {
        LabeledContent("导入", value: "拖拽图片文件")
    }
}

#endif
