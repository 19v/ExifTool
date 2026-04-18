//
//  ManualPhotoPickerAccessView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

import SwiftUI

struct ManualPhotoPickerAccessView: View {
    @ObservedObject var picker: ManualPhotoPickerViewModel
    let readOnlyMode: Bool

    var body: some View {
        ManualPhotoPickerContent(
            picker: picker,
            readOnlyMode: readOnlyMode,
            emptyTitle: "未授权系统照片库",
            emptyDescription: "可以直接点加号手动选择一张图片查看 Exif。"
        )
    }
}

#endif
