//
//  MetadataSectionView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct MetadataSectionView: View {
    let section: MetadataSection
    let showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MetadataDisplayLocalizer.sectionTitle(section, showsChinese: showsChineseKeys))
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        MetadataKeyLabel(englishKey: item.key, showsChinese: showsChineseKeys)
                        Text(item.value)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(highlightedMetadataKeys.contains(item.key) ? Color.accentColor.opacity(0.12) : Color.clear)

                    if item.id != section.items.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
