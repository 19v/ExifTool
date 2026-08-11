#if os(macOS)

//
//  MetadataKeyLabel.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct MacMetadataKeyLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .frame(width: 120, alignment: .leading)
            .accessibilityLabel(title)
    }
}

#endif

