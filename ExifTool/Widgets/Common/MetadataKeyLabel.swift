//
//  MetadataKeyLabel.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct MetadataKeyLabel: View {
    let englishKey: String
    let showsChinese: Bool

    var body: some View {
        Text(displayKey)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .frame(width: 120, alignment: .leading)
            .accessibilityLabel(displayKey)
    }

    private var displayKey: String {
        if showsChinese, let chineseKey = MetadataKeyTranslator.chineseName(for: englishKey) {
            return chineseKey
        }

        return englishKey
    }
}
