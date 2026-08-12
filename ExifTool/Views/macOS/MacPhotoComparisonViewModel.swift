#if os(macOS)

import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class MacPhotoComparisonViewModel {
    private(set) var primaryMetadata = PhotoDetailState.loading
    private(set) var compareMetadata = PhotoDetailState.loading
    private(set) var snapshot = MacPhotoComparisonSnapshot.empty
    private(set) var isExporting = false
    private(set) var feedback: MacPhotoComparisonFeedback?

    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?

    func load(primaryAsset: PhotoAsset, compareAsset: PhotoAsset?) async {
        let currentRequestID = UUID()
        requestID = currentRequestID
        primaryMetadata = .loading
        compareMetadata = .loading
        snapshot = .empty

        guard let compareAsset else {
            return
        }

        async let leftMetadata = PhotoLoader.metadata(for: primaryAsset, allowNetwork: false)
        async let rightMetadata = PhotoLoader.metadata(for: compareAsset, allowNetwork: false)
        let (leftDetail, rightDetail) = await (leftMetadata, rightMetadata)

        guard !Task.isCancelled, currentRequestID == requestID else {
            return
        }
        primaryMetadata = leftDetail
        compareMetadata = rightDetail

        guard case .loaded(let leftMetadata) = leftDetail,
              case .loaded(let rightMetadata) = rightDetail else {
            return
        }

        let newSnapshot = await MediaProcessing.run {
            MacPhotoComparisonSnapshot(leftMetadata: leftMetadata, rightMetadata: rightMetadata)
        }
        guard !Task.isCancelled, currentRequestID == requestID else {
            return
        }
        snapshot = newSnapshot
    }

    func copyReport(primaryAsset: PhotoAsset, compareAsset: PhotoAsset, showingOnlyDifferences: Bool) {
        let report = reportMarkdown(
            primaryAsset: primaryAsset,
            compareAsset: compareAsset,
            showingOnlyDifferences: showingOnlyDifferences
        )
        guard !report.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        showFeedback(.copied)
    }

    func exportReport(primaryAsset: PhotoAsset, compareAsset: PhotoAsset, showingOnlyDifferences: Bool) {
        let report = reportMarkdown(
            primaryAsset: primaryAsset,
            compareAsset: compareAsset,
            showingOnlyDifferences: showingOnlyDifferences
        )
        guard !report.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.title = AppLocalization.string("mac.comparison.exportPanelTitle")
        panel.nameFieldStringValue = comparisonFileName(primaryAsset: primaryAsset, compareAsset: compareAsset)
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isExporting = true
        defer { isExporting = false }
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            showFeedback(.exported(url))
        } catch {
            showFeedback(.exportFailed)
            NSSound.beep()
        }
    }

    private func reportMarkdown(
        primaryAsset: PhotoAsset,
        compareAsset: PhotoAsset,
        showingOnlyDifferences: Bool
    ) -> String {
        guard case .loaded = primaryMetadata, case .loaded = compareMetadata else {
            return ""
        }

        let leftName = primaryAsset.displayName ?? primaryAsset.id
        let rightName = compareAsset.displayName ?? compareAsset.id
        let sections = snapshot.sections(showingOnlyDifferences: showingOnlyDifferences)
        var lines = [
            "# \(AppLocalization.string("mac.comparison.report.title"))",
            "",
            "- \(AppLocalization.string("mac.comparison.report.left")): \(leftName)",
            "- \(AppLocalization.string("mac.comparison.report.right")): \(rightName)",
            "- \(AppLocalization.string("mac.comparison.report.differenceCount")): \(snapshot.differingMetadataKeys.count)",
            ""
        ]

        if !snapshot.differenceSummaryItems.isEmpty {
            lines.append("## \(AppLocalization.string("mac.comparison.report.summary"))")
            lines.append("")
            for item in snapshot.differenceSummaryItems {
                lines.append("- \(item.label): \(item.leftValue) -> \(item.rightValue)")
            }
            lines.append("")
        }

        for section in sections {
            lines.append("## \(section.title)")
            lines.append("")
            for row in section.rows {
                let marker = AppLocalization.string(
                    row.isDifferent ? "mac.comparison.report.different" : "mac.comparison.report.same"
                )
                lines.append("- \(row.label) [\(marker)]")
                lines.append("  \(AppLocalization.string("mac.comparison.report.left")): \(row.leftValue)")
                lines.append("  \(AppLocalization.string("mac.comparison.report.right")): \(row.rightValue)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func comparisonFileName(primaryAsset: PhotoAsset, compareAsset: PhotoAsset) -> String {
        let leftName = sanitizedFileName(primaryAsset.displayName ?? "photo-a")
        let rightName = sanitizedFileName(compareAsset.displayName ?? "photo-b")
        return "\(leftName)-vs-\(rightName).md"
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    private func showFeedback(_ newFeedback: MacPhotoComparisonFeedback) {
        feedbackTask?.cancel()
        feedback = newFeedback
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, self?.feedback == newFeedback else {
                return
            }
            self?.feedback = nil
        }
    }
}

#endif
