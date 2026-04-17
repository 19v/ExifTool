//
//  ManualPhotoPickerTabView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

internal import PhotosUI
import SwiftUI

struct ManualPhotoPickerTabView: View {
    @ObservedObject var picker: ManualPhotoPickerViewModel
    let readOnlyMode: Bool

    var body: some View {
        NavigationStack {
            ManualPhotoPickerContent(picker: picker, readOnlyMode: readOnlyMode)
                .navigationTitle("选图")
                .platformInlineNavigationTitle()
        }
    }
}

#endif
