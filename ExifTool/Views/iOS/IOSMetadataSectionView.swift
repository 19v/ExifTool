#if os(iOS)

//
//  MetadataSectionView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct MetadataSectionView: View {
    let section: MetadataDisplaySection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline)

            if section.itemGroups.isEmpty {
                metadataRows(section.items)
            } else {
                ForEach(section.itemGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                        metadataRows(group.items)
                    }
                }
            }
        }
    }

    private func metadataRows(_ items: [MetadataDisplayItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    MetadataKeyLabel(title: item.title)
                    Text(item.value)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(item.isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)

                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
        .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

#endif

