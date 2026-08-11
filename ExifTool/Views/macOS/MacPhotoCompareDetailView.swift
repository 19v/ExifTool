//
//  MacPhotoCompareDetailView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacPhotoCompareDetailView: View {
    let assets: [PhotoAsset]
    let primaryAsset: PhotoAsset
    @Binding var compareAssetID: String?
    let readOnlyMode: Bool

    @State private var primaryMetadata = PhotoDetailState.loading
    @State private var compareMetadata = PhotoDetailState.loading
    @State private var showsOnlyDifferences = false
    @State private var showsChineseKeys: Bool
    @State private var isExportingComparison = false
    @State private var comparisonFeedback: MacPhotoComparisonFeedback?
    @State private var comparisonSnapshot = MacPhotoComparisonSnapshot.empty

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

    private var compareAsset: PhotoAsset? {
        if let compareAssetID {
            return compareCandidates.first(where: { $0.id == compareAssetID })
        }

        return compareCandidates.first
    }

    var body: some View {
        VStack(spacing: 0) {
            MacComparisonHeader(
                differenceCount: comparisonSnapshot.differingMetadataKeys.count,
                showsOnlyDifferences: $showsOnlyDifferences,
                feedback: comparisonFeedback,
                canExport: !comparisonSnapshot.differenceSummaryItems.isEmpty,
                isExporting: isExportingComparison,
                candidates: compareCandidates,
                selection: compareSelection,
                onCopy: copyComparisonReport,
                onExport: exportComparisonReport
            )

            MacDifferenceSummaryStrip(items: comparisonSnapshot.differenceSummaryItems)

            if let compareAsset {
                HSplitView {
                    MacComparisonColumn(
                        title: "当前照片",
                        asset: primaryAsset,
                        detail: primaryMetadata,
                        readOnlyMode: readOnlyMode,
                        showsChineseKeys: $showsChineseKeys,
                        highlightedMetadataKeys: comparisonSnapshot.differingMetadataKeys,
                        visibleMetadataKeys: showsOnlyDifferences ? comparisonSnapshot.differingMetadataKeys : nil
                    )
                    MacComparisonColumn(
                        title: "对比照片",
                        asset: compareAsset,
                        detail: compareMetadata,
                        readOnlyMode: readOnlyMode,
                        showsChineseKeys: $showsChineseKeys,
                        highlightedMetadataKeys: comparisonSnapshot.differingMetadataKeys,
                        visibleMetadataKeys: showsOnlyDifferences ? comparisonSnapshot.differingMetadataKeys : nil
                    )
                }
            } else {
                ContentUnavailableView("没有可对比的第二张照片", systemImage: "rectangle.split.2x1")
            }
        }
        .navigationTitle("对比查看")
        .task(id: comparisonTaskID) {
            await loadComparisonMetadata()
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

    private func loadComparisonMetadata() async {
        guard let compareAsset else {
            primaryMetadata = .loading
            compareMetadata = .loading
            comparisonSnapshot = .empty
            return
        }

        async let leftMetadata = PhotoLoader.metadata(for: primaryAsset, allowNetwork: false)
        async let rightMetadata = PhotoLoader.metadata(for: compareAsset, allowNetwork: false)

        let (leftDetail, rightDetail) = await (leftMetadata, rightMetadata)
        primaryMetadata = leftDetail
        compareMetadata = rightDetail

        guard case .loaded(let leftMetadata) = leftDetail,
              case .loaded(let rightMetadata) = rightDetail else {
            comparisonSnapshot = .empty
            return
        }

        comparisonSnapshot = MacPhotoComparisonSnapshot(
            leftMetadata: leftMetadata,
            rightMetadata: rightMetadata
        )
    }

    private func copyComparisonReport() {
        let report = comparisonReportMarkdown
        guard !report.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        showFeedback(.copied)
    }

    private func exportComparisonReport() {
        let report = comparisonReportMarkdown
        guard !report.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = AppLocalization.string("mac.comparison.exportPanelTitle")
        panel.nameFieldStringValue = comparisonFileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isExportingComparison = true
        defer { isExportingComparison = false }

        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            showFeedback(.exported(url))
        } catch {
            showFeedback(.exportFailed)
            NSSound.beep()
        }
    }

    private func showFeedback(_ feedback: MacPhotoComparisonFeedback) {
        comparisonFeedback = feedback

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if comparisonFeedback == feedback {
                comparisonFeedback = nil
            }
        }
    }

    private var comparisonFileName: String {
        let leftName = sanitizedFileName(primaryAsset.displayName ?? "photo-a")
        let rightName = sanitizedFileName(compareAsset?.displayName ?? "photo-b")
        return "\(leftName)-vs-\(rightName).md"
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    private var comparisonReportMarkdown: String {
        guard let compareAsset,
              case .loaded = primaryMetadata,
              case .loaded = compareMetadata else {
            return ""
        }

        let leftName = primaryAsset.displayName ?? primaryAsset.id
        let rightName = compareAsset.displayName ?? compareAsset.id
        let sections = comparisonSnapshot.sections(showingOnlyDifferences: showsOnlyDifferences)

        var lines: [String] = [
            "# 照片对比结果",
            "",
            "- 左侧：\(leftName)",
            "- 右侧：\(rightName)",
            "- 差异字段数：\(comparisonSnapshot.differingMetadataKeys.count)",
            ""
        ]

        if !comparisonSnapshot.differenceSummaryItems.isEmpty {
            lines.append("## 差异摘要")
            lines.append("")
            for item in comparisonSnapshot.differenceSummaryItems {
                lines.append("- \(item.label): \(item.leftValue) -> \(item.rightValue)")
            }
            lines.append("")
        }

        for section in sections {
            lines.append("## \(section.title)")
            lines.append("")

            for row in section.rows {
                let marker = row.isDifferent ? "不同" : "相同"
                lines.append("- \(row.label) [\(marker)]")
                lines.append("  左侧：\(row.leftValue)")
                lines.append("  右侧：\(row.rightValue)")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

}

private struct MacComparisonHeader: View {
    let differenceCount: Int
    @Binding var showsOnlyDifferences: Bool
    let feedback: MacPhotoComparisonFeedback?
    let canExport: Bool
    let isExporting: Bool
    let candidates: [PhotoAsset]
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
                ForEach(candidates) { asset in
                    Text(asset.displayName ?? "照片").tag(Optional(asset.id))
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
