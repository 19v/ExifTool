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
    let onPhotoViewed: (() -> Void)?
    let onPhotoDetailVisibilityChanged: ((Bool) -> Void)?
    let showsLibraryAccessPrompt: Bool
    let onRequestLibraryAccess: (() -> Void)?

    init(
        picker: ManualPhotoPickerViewModel,
        readOnlyMode: Bool,
        onPhotoViewed: (() -> Void)? = nil,
        onPhotoDetailVisibilityChanged: ((Bool) -> Void)? = nil,
        showsLibraryAccessPrompt: Bool = false,
        onRequestLibraryAccess: (() -> Void)? = nil
    ) {
        self.picker = picker
        self.readOnlyMode = readOnlyMode
        self.onPhotoViewed = onPhotoViewed
        self.onPhotoDetailVisibilityChanged = onPhotoDetailVisibilityChanged
        self.showsLibraryAccessPrompt = showsLibraryAccessPrompt
        self.onRequestLibraryAccess = onRequestLibraryAccess
    }

    var body: some View {
        NavigationStack {
            ManualPhotoPickerContent(
                picker: picker,
                readOnlyMode: readOnlyMode,
                onPhotoViewed: onPhotoViewed,
                onPhotoDetailVisibilityChanged: onPhotoDetailVisibilityChanged,
                showsLibraryAccessPrompt: showsLibraryAccessPrompt,
                onRequestLibraryAccess: onRequestLibraryAccess
            )
        }
    }
}

#endif
