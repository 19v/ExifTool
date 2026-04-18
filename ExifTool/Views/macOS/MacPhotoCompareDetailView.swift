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

    private var differenceSummaryItems: [DifferenceSummaryItem] {
        guard case .loaded(let leftMetadata) = primaryMetadata,
              case .loaded(let rightMetadata) = compareMetadata else {
            return []
        }

        let leftValues = metadataValueMap(for: leftMetadata)
        let rightValues = metadataValueMap(for: rightMetadata)
        let preferredKeys = [
            "DateTimeOriginal",
            "Make",
            "Model",
            "LensModel",
            "FocalLength",
            "FNumber",
            "ExposureTime",
            "ISOSpeedRatings",
            "ExposureBiasValue",
            "WhiteBalance",
            "Flash",
            "PixelXDimension",
            "PixelYDimension"
        ]

        return preferredKeys.compactMap { key in
            guard let leftValue = leftValues[key],
                  let rightValue = rightValues[key],
                  leftValue != rightValue else {
                return nil
            }

            return DifferenceSummaryItem(
                key: key,
                label: MetadataKeyTranslator.chineseName(for: key) ?? key,
                leftValue: leftValue,
                rightValue: rightValue
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("对比模式")
                    .font(.headline)

                if !differingMetadataKeys.isEmpty {
                    Text("已标出 \(differingMetadataKeys.count) 个不同字段")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("只看不同", isOn: $showsOnlyDifferences)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if !differenceSummaryItems.isEmpty {
                    if let comparisonFeedback {
                        Text(comparisonFeedback.message)
                            .font(.footnote)
                            .foregroundStyle(comparisonFeedback.color)
                            .lineLimit(1)
                    }

                    Button("复制对比") {
                        copyComparisonReport()
                    }

                    Button("导出 Markdown") {
                        exportComparisonReport()
                    }
                    .disabled(isExportingComparison)
                }

                Picker("对比照片", selection: compareSelection) {
                    ForEach(compareCandidates) { asset in
                        Text(asset.displayName ?? "照片").tag(Optional(asset.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.regularMaterial)

            if !differenceSummaryItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(differenceSummaryItems) { item in
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

            if let compareAsset {
                HSplitView {
                    compareColumn(title: "当前照片", asset: primaryAsset)
                    compareColumn(title: "对比照片", asset: compareAsset)
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

    private func compareColumn(title: String, asset: PhotoAsset) -> some View {
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

            PhotoDetailPage(
                asset: asset,
                readOnlyMode: readOnlyMode,
                showsChineseKeys: $showsChineseKeys,
                navigationTitle: asset.displayName ?? title,
                highlightedMetadataKeys: differingMetadataKeys,
                visibleMetadataKeys: showsOnlyDifferences ? differingMetadataKeys : nil
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var comparisonTaskID: String {
        "\(primaryAsset.id)-\(compareAsset?.id ?? "none")"
    }

    private var differingMetadataKeys: Set<String> {
        guard case .loaded(let leftMetadata) = primaryMetadata,
              case .loaded(let rightMetadata) = compareMetadata else {
            return []
        }

        let leftValues = metadataValueMap(for: leftMetadata)
        let rightValues = metadataValueMap(for: rightMetadata)
        let keys = Set(leftValues.keys).union(rightValues.keys)

        return Set(keys.filter { leftValues[$0] != rightValues[$0] })
    }

    private func metadataValueMap(for metadata: PhotoMetadata) -> [String: String] {
        var values: [String: String] = [:]

        for section in metadata.sections {
            for item in section.items {
                values[item.key] = item.value
            }
        }

        if let coordinate = metadata.coordinate {
            values["__coordinate__"] = LocationFormatter.coordinateText(coordinate)
        }

        return values
    }

    private func loadComparisonMetadata() async {
        guard let compareAsset else {
            primaryMetadata = .loading
            compareMetadata = .loading
            return
        }

        async let leftMetadata = PhotoLoader.metadata(for: primaryAsset, allowNetwork: false)
        async let rightMetadata = PhotoLoader.metadata(for: compareAsset, allowNetwork: false)

        primaryMetadata = await leftMetadata
        compareMetadata = await rightMetadata
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
              case .loaded(let leftMetadata) = primaryMetadata,
              case .loaded(let rightMetadata) = compareMetadata else {
            return ""
        }

        let leftName = primaryAsset.displayName ?? primaryAsset.id
        let rightName = compareAsset.displayName ?? compareAsset.id
        let keysToExport = showsOnlyDifferences
            ? differingMetadataKeys
            : Set(metadataValueMap(for: leftMetadata).keys).union(metadataValueMap(for: rightMetadata).keys)
        let sections = comparisonSections(
            leftMetadata: leftMetadata,
            rightMetadata: rightMetadata,
            keys: keysToExport
        )

        var lines: [String] = [
            "# 照片对比结果",
            "",
            "- 左侧：\(leftName)",
            "- 右侧：\(rightName)",
            "- 差异字段数：\(differingMetadataKeys.count)",
            ""
        ]

        if !differenceSummaryItems.isEmpty {
            lines.append("## 差异摘要")
            lines.append("")
            for item in differenceSummaryItems {
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

    private func comparisonSections(
        leftMetadata: PhotoMetadata,
        rightMetadata: PhotoMetadata,
        keys: Set<String>
    ) -> [ComparisonSection] {
        let leftValues = metadataValueMap(for: leftMetadata)
        let rightValues = metadataValueMap(for: rightMetadata)
        let orderedTitles = leftMetadata.sections.map(\.title) + rightMetadata.sections.map(\.title)
        let uniqueTitles = orderedTitles.reduce(into: [String]()) { partialResult, title in
            if !partialResult.contains(title) {
                partialResult.append(title)
            }
        }

        return uniqueTitles.compactMap { title in
            let leftSection = leftMetadata.sections.first(where: { $0.title == title })
            let rightSection = rightMetadata.sections.first(where: { $0.title == title })
            let orderedKeys = ((leftSection?.items ?? []) + (rightSection?.items ?? [])).map(\.key)
            let uniqueKeys = orderedKeys.reduce(into: [String]()) { partialResult, key in
                if keys.contains(key), !partialResult.contains(key) {
                    partialResult.append(key)
                }
            }

            let rows = uniqueKeys.compactMap { key -> ComparisonRow? in
                let leftValue = leftValues[key] ?? "-"
                let rightValue = rightValues[key] ?? "-"
                guard keys.contains(key) else {
                    return nil
                }

                return ComparisonRow(
                    key: key,
                    label: MetadataKeyTranslator.chineseName(for: key) ?? key,
                    leftValue: leftValue,
                    rightValue: rightValue,
                    isDifferent: leftValue != rightValue
                )
            }

            guard !rows.isEmpty else {
                return nil
            }

            return ComparisonSection(title: title, rows: rows)
        }
    }
}

#endif
