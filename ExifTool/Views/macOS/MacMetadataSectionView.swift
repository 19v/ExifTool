#if os(macOS)

//
//  MetadataSectionView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct MacMetadataSectionView: View {
    let section: MetadataSection
    let showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MetadataDisplayLocalizer.sectionTitle(section, showsChinese: showsChineseKeys))
                .font(.headline)

            if section.itemGroups.isEmpty {
                metadataRows(section.items)
            } else {
                ForEach(section.itemGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(MetadataDisplayLocalizer.sectionTitle(
                            MetadataSection(id: group.id, title: group.title, items: group.items),
                            showsChinese: showsChineseKeys
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                        metadataRows(group.items)
                    }
                }
            }
        }
    }

    private func metadataRows(_ items: [MetadataItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    MacMetadataKeyLabel(englishKey: item.key, showsChinese: showsChineseKeys)
                    Text(MetadataDisplayLocalizer.valueText(item.value, showsChinese: showsChineseKeys))
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(highlightedMetadataKeys.contains(item.key) ? Color.accentColor.opacity(0.12) : Color.clear)

                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
        .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

#endif


