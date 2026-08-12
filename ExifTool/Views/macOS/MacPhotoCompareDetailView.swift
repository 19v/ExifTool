//
//  MacPhotoCompareDetailView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import SwiftUI

struct MacPhotoCompareDetailView: View {
    let assets: [PhotoAsset]
    let primaryAsset: PhotoAsset
    @Binding var compareAssetID: String?
    let readOnlyMode: Bool

    @State private var showsOnlyDifferences = false
    @State private var showsChineseKeys: Bool
    @State private var model = MacPhotoComparisonViewModel()

    init(
        assets: [PhotoAsset],
        primaryAsset: PhotoAsset,
        compareAssetID: Binding<String?>,
        readOnlyMode: Bool
    ) {
        self.assets = assets
        self.primaryAsset = primaryAsset
        _compareAssetID = compareAssetID
        self.readOnlyMode = readOnlyMode
        _showsChineseKeys = State(initialValue: MetadataLanguagePreference.defaultShowsChineseKeys)
    }

    private var compareCandidates: [PhotoAsset] {
        assets.filter { $0.id != primaryAsset.id }
    }

    private var candidateOptions: [MacComparisonCandidate] {
        compareCandidates.map {
            MacComparisonCandidate(
                id: $0.id,
                title: $0.displayName ?? String(localized: "照片")
            )
        }
    }

    private var compareAsset: PhotoAsset? {
        if let compareAssetID {
            return compareCandidates.first(where: { $0.id == compareAssetID })
        }

        return compareCandidates.first
    }

    var body: some View {
        VStack(spacing: 0) {
            MacComparisonHeader(
                differenceCount: model.snapshot.differingMetadataKeys.count,
                showsOnlyDifferences: $showsOnlyDifferences,
                feedback: model.feedback,
                canExport: !model.snapshot.differenceSummaryItems.isEmpty,
                isExporting: model.isExporting,
                candidates: candidateOptions,
                selection: compareSelection,
                onCopy: copyComparisonReport,
                onExport: exportComparisonReport
            )

            MacDifferenceSummaryStrip(items: model.snapshot.differenceSummaryItems)

            if let compareAsset {
                HSplitView {
                    MacComparisonColumn(
                        title: "当前照片",
                        asset: primaryAsset,
                        detail: model.primaryMetadata,
                        readOnlyMode: readOnlyMode,
                        showsChineseKeys: $showsChineseKeys,
                        highlightedMetadataKeys: model.snapshot.differingMetadataKeys,
                        visibleMetadataKeys: showsOnlyDifferences ? model.snapshot.differingMetadataKeys : nil
                    )
                    MacComparisonColumn(
                        title: "对比照片",
                        asset: compareAsset,
                        detail: model.compareMetadata,
                        readOnlyMode: readOnlyMode,
                        showsChineseKeys: $showsChineseKeys,
                        highlightedMetadataKeys: model.snapshot.differingMetadataKeys,
                        visibleMetadataKeys: showsOnlyDifferences ? model.snapshot.differingMetadataKeys : nil
                    )
                }
            } else {
                ContentUnavailableView("没有可对比的第二张照片", systemImage: "rectangle.split.2x1")
            }
        }
        .navigationTitle("对比查看")
        .task(id: comparisonTaskID) {
            await model.load(primaryAsset: primaryAsset, compareAsset: compareAsset)
        }
    }

    private var compareSelection: Binding<String?> {
        Binding {
            compareAsset?.id
        } set: { newValue in
            compareAssetID = newValue
        }
    }

    private var comparisonTaskID: String {
        "\(primaryAsset.id)-\(compareAsset?.id ?? "none")"
    }

    private func copyComparisonReport() {
        guard let compareAsset else { return }
        model.copyReport(
            primaryAsset: primaryAsset,
            compareAsset: compareAsset,
            showingOnlyDifferences: showsOnlyDifferences
        )
    }

    private func exportComparisonReport() {
        guard let compareAsset else { return }
        model.exportReport(
            primaryAsset: primaryAsset,
            compareAsset: compareAsset,
            showingOnlyDifferences: showsOnlyDifferences
        )
    }

}

private struct MacComparisonCandidate: Identifiable, Hashable {
    let id: String
    let title: String
}

private struct MacComparisonHeader: View {
    let differenceCount: Int
    @Binding var showsOnlyDifferences: Bool
    let feedback: MacPhotoComparisonFeedback?
    let canExport: Bool
    let isExporting: Bool
    let candidates: [MacComparisonCandidate]
    @Binding var selection: String?
    let onCopy: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("对比模式")
                .font(.headline)

            if differenceCount > 0 {
                Text("已标出 \(differenceCount) 个不同字段")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("只看不同", isOn: $showsOnlyDifferences)
                .toggleStyle(.switch)
                .controlSize(.small)

            if canExport {
                if let feedback {
                    Text(feedback.message)
                        .font(.footnote)
                        .foregroundStyle(feedback.color)
                        .lineLimit(1)
                }

                Button("复制对比", action: onCopy)
                Button("导出 Markdown", action: onExport)
                    .disabled(isExporting)
            }

            Picker("对比照片", selection: $selection) {
                ForEach(candidates) { candidate in
                    Text(candidate.title).tag(Optional(candidate.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

private struct MacDifferenceSummaryStrip: View {
    let items: [DifferenceSummaryItem]

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(item.leftValue) -> \(item.rightValue)")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .background(Color.platformSecondaryBackground.opacity(0.55))
        }
    }
}

private struct MacComparisonColumn: View {
    let title: String
    let asset: PhotoAsset
    let detail: PhotoDetailState
    let readOnlyMode: Bool
    @Binding var showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(asset.displayName ?? "照片")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            MacPhotoDetailPage(
                asset: asset,
                readOnlyMode: readOnlyMode,
                showsChineseKeys: $showsChineseKeys,
                navigationTitle: asset.displayName ?? title,
                highlightedMetadataKeys: highlightedMetadataKeys,
                visibleMetadataKeys: visibleMetadataKeys,
                suppliedDetail: detail
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
