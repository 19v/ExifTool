//
//  PhotoViews+macOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Color {
    static var platformSecondaryBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        self
    }

    @ViewBuilder
    func platformDetailPagingStyle() -> some View {
        self
    }

    @ViewBuilder
    func platformTabBarHidden() -> some View {
        self
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

extension ToolbarItemPlacement {
    static var platformLanguageToggle: ToolbarItemPlacement {
        .primaryAction
    }
}

struct PlatformAlbumList: View {
    let albums: [PhotoAlbum]
    let readOnlyMode: Bool

    var body: some View {
        List(albums) { album in
            NavigationLink {
                AlbumDetailView(album: album, readOnlyMode: readOnlyMode)
            } label: {
                AlbumRowView(album: album)
            }
        }
        .listStyle(.sidebar)
    }
}

struct PlatformSettingsImportSource: View {
    var body: some View {
        LabeledContent("导入", value: "拖拽图片文件")
    }
}

struct PlatformPhotoGridScrollScrubber: View {
    var body: some View {
        EmptyView()
    }
}

struct MacPhotoDropTabView: View {
    let readOnlyMode: Bool

    @EnvironmentObject private var workspace: MacPhotoWorkspace
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false
    @State private var isImporterPresented = false
    @State private var isCompareModeEnabled = false
    @State private var compareAssetID: String?

    var body: some View {
        NavigationStack {
            Group {
                if workspace.sortedAssets.isEmpty {
                    MacPhotoDropPlaceholder(
                        isDropTargeted: isDropTargeted,
                        recentFiles: workspace.recentFiles,
                        onPickFiles: { isImporterPresented = true },
                        onOpenRecentFile: { url in
                            _ = workspace.openRecentFile(url)
                        },
                        onClearRecentFiles: {
                            workspace.clearRecentFiles()
                        }
                    )
                } else {
                    NavigationSplitView {
                        MacDroppedPhotoSidebar(
                            assets: workspace.sortedAssets,
                            selectedAssetID: $workspace.selectedAssetID
                        )
                    } detail: {
                        if let selectedAsset = selectedAsset {
                            if isCompareModeEnabled, workspace.sortedAssets.count > 1 {
                                MacPhotoCompareDetailView(
                                    assets: workspace.sortedAssets,
                                    primaryAsset: selectedAsset,
                                    compareAssetID: $compareAssetID,
                                    readOnlyMode: readOnlyMode
                                )
                            } else {
                                PhotoDetailView(
                                    assets: workspace.sortedAssets,
                                    initialAssetID: selectedAsset.id,
                                    readOnlyMode: readOnlyMode
                                )
                                .id(selectedAsset.id)
                            }
                        } else {
                            ContentUnavailableView("没有选中的照片", systemImage: "photo")
                        }
                    }
                }
            }
            .navigationTitle(workspace.windowTitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("选择文件") {
                        workspace.pickFiles()
                    }

                    if !workspace.sortedAssets.isEmpty {
                        Button {
                            workspace.selectPreviousAsset()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .help("上一张")
                        .disabled(!workspace.canSelectPreviousAsset)

                        Button {
                            workspace.selectNextAsset()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .help("下一张")
                        .disabled(!workspace.canSelectNextAsset)
                    }

                    if workspace.sortedAssets.count > 1 {
                        Button(isCompareModeEnabled ? "关闭对比" : "对比") {
                            isCompareModeEnabled.toggle()
                            ensureCompareSelection()
                        }
                        .help(isCompareModeEnabled ? "关闭对比模式" : "左右对比两张照片")
                    }

                    if !workspace.recentFiles.isEmpty {
                        Menu("最近打开") {
                            ForEach(workspace.recentFiles, id: \.self) { url in
                                Button(url.lastPathComponent) {
                                    _ = workspace.openRecentFile(url)
                                }
                            }

                            Divider()

                            Button("清除最近记录") {
                                workspace.clearRecentFiles()
                            }
                        }
                    }

                    if !workspace.sortedAssets.isEmpty {
                        if workspace.hasCurrentFile {
                            Button("新窗口打开") {
                                guard let filePath = workspace.currentFilePath else {
                                    return
                                }

                                openWindow(id: macPhotoViewerWindowID, value: filePath)
                            }

                            Button("复制路径") {
                                workspace.copyCurrentFilePath()
                            }

                            Button("默认应用打开") {
                                workspace.openCurrentFileInDefaultApp()
                            }

                            Button("在 Finder 中显示") {
                                workspace.revealCurrentFileInFinder()
                            }
                        }

                        Menu("排序") {
                            Picker("排序", selection: $workspace.sortMode) {
                                ForEach(MacPhotoWorkspace.SortMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                        }

                        Button("清空") {
                            workspace.clear()
                        }
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            workspace.importFiles(from: urls)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                return
            }

            _ = workspace.importFiles(from: urls)
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                workspace.selectPreviousAsset()
            case .right:
                workspace.selectNextAsset()
            default:
                break
            }
        }
        .onAppear {
            ensureCompareSelection()
        }
        .onChange(of: workspace.selectedAssetID) { _, _ in
            ensureCompareSelection()
        }
        .onChange(of: workspace.sortedAssets.map(\.id)) { _, _ in
            ensureCompareSelection()
        }
    }

    private var selectedAsset: PhotoAsset? {
        guard let selectedAssetID = workspace.selectedAssetID else {
            return workspace.sortedAssets.first
        }

        return workspace.sortedAssets.first(where: { $0.id == selectedAssetID })
    }

    private func ensureCompareSelection() {
        let assetIDs = Set(workspace.sortedAssets.map(\.id))
        if let compareAssetID, !assetIDs.contains(compareAssetID) {
            self.compareAssetID = nil
        }

        guard let selectedAsset else {
            compareAssetID = nil
            isCompareModeEnabled = false
            return
        }

        if compareAssetID == selectedAsset.id {
            compareAssetID = nil
        }

        if isCompareModeEnabled && compareAssetID == nil {
            compareAssetID = workspace.sortedAssets.first(where: { $0.id != selectedAsset.id })?.id
        }

        if workspace.sortedAssets.count < 2 {
            isCompareModeEnabled = false
            compareAssetID = nil
        }
    }
}

private struct MacPhotoDropPlaceholder: View {
    let isDropTargeted: Bool
    let recentFiles: [URL]
    let onPickFiles: () -> Void
    let onOpenRecentFile: (URL) -> Void
    let onClearRecentFiles: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)

            Text("拖入照片开始查看 Exif")
                .font(.title3.weight(.semibold))

            Text("把 JPEG、HEIC、PNG、TIFF 等图片文件直接拖到窗口里，应用会立即显示预览和元数据。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("选择文件") {
                onPickFiles()
            }
            .buttonStyle(.borderedProminent)

            Text("也可以直接按 Cmd+O 选择文件。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("最近打开")
                            .font(.headline)

                        Spacer()

                        Button("清除") {
                            onClearRecentFiles()
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(recentFiles, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            onOpenRecentFile(url)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.platformSecondaryBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [8, 8]))
                }
                .padding(24)
        )
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
    }
}

private struct MacDroppedPhotoSidebar: View {
    let assets: [PhotoAsset]
    @Binding var selectedAssetID: String?

    var body: some View {
        List(assets, selection: $selectedAssetID) { asset in
            MacDroppedPhotoRow(asset: asset)
                .tag(asset.id)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }
}

private struct MacDroppedPhotoRow: View {
    let asset: PhotoAsset

    var body: some View {
        HStack(spacing: 10) {
            PhotoThumbnail(asset: asset)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.displayName ?? "照片")
                    .font(.headline)
                    .lineLimit(1)

                Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MacPhotoCompareDetailView: View {
    private enum ComparisonFeedback: Equatable {
        case copied
        case exported(URL)
        case exportFailed

        var message: String {
            switch self {
            case .copied:
                return "对比结果已复制到剪贴板"
            case .exported(let url):
                return "已导出到 \(url.lastPathComponent)"
            case .exportFailed:
                return "导出失败，请稍后重试"
            }
        }

        var color: Color {
            switch self {
            case .exportFailed:
                return .red
            case .copied, .exported:
                return .secondary
            }
        }
    }

    let assets: [PhotoAsset]
    let primaryAsset: PhotoAsset
    @Binding var compareAssetID: String?
    let readOnlyMode: Bool

    @State private var primaryMetadata = PhotoDetailState.loading
    @State private var compareMetadata = PhotoDetailState.loading
    @State private var showsOnlyDifferences = false
    @State private var isExportingComparison = false
    @State private var comparisonFeedback: ComparisonFeedback?

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
                showsChineseKeys: false,
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
        panel.title = "导出对比结果"
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

    private func showFeedback(_ feedback: ComparisonFeedback) {
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
        let keysToExport = showsOnlyDifferences ? differingMetadataKeys : Set(metadataValueMap(for: leftMetadata).keys).union(metadataValueMap(for: rightMetadata).keys)
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

private struct DifferenceSummaryItem: Identifiable {
    let key: String
    let label: String
    let leftValue: String
    let rightValue: String

    var id: String { key }
}

private struct ComparisonSection: Identifiable {
    let title: String
    let rows: [ComparisonRow]

    var id: String { title }
}

private struct ComparisonRow: Identifiable {
    let key: String
    let label: String
    let leftValue: String
    let rightValue: String
    let isDifferent: Bool

    var id: String { key }
}

#endif
