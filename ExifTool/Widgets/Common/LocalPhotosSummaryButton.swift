//
//  LocalPhotosSummaryButton.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct LocalPhotosSummaryButton: View {
    let snapshot: LocalPhotosStatusSnapshot
    let iconName: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LocalPhotosStatusContent(
                snapshot: snapshot,
                trailingSystemImageName: iconName
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }
}
