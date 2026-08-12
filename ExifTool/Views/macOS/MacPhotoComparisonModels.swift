#if os(macOS)

import ImageIO
import SwiftUI

nonisolated struct ComparisonRow: Identifiable, Equatable, Sendable {
    let id: String
    let key: String
    let label: String
    let leftValue: String
    let rightValue: String
    let isDifferent: Bool
}

nonisolated struct ComparisonSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [ComparisonRow]
}

nonisolated struct DifferenceSummaryItem: Identifiable, Equatable, Sendable {
    let key: String
    let label: String
    let leftValue: String
    let rightValue: String

    var id: String { key }
}

nonisolated struct MacPhotoComparisonSnapshot: Equatable, Sendable {
    static let empty = MacPhotoComparisonSnapshot(
        differingMetadataKeys: [],
        differenceSummaryItems: [],
        allSections: [],
        differingSections: []
    )

    let differingMetadataKeys: Set<String>
    let differenceSummaryItems: [DifferenceSummaryItem]
    let allSections: [ComparisonSection]
    let differingSections: [ComparisonSection]

    init(leftMetadata: PhotoMetadata, rightMetadata: PhotoMetadata) {
        let leftEntries = Self.comparisonEntries(for: leftMetadata)
        let rightEntries = Self.comparisonEntries(for: rightMetadata)
        let leftEntriesByID = Self.entriesByID(leftEntries)
        let rightEntriesByID = Self.entriesByID(rightEntries)
        let orderedEntryIDs = Self.uniqueValues((leftEntries + rightEntries).map(\.id))
        let differingEntryIDs = Set(orderedEntryIDs.filter {
            leftEntriesByID[$0]?.value != rightEntriesByID[$0]?.value
        })

        differingMetadataKeys = Set(differingEntryIDs.compactMap { entryID in
            leftEntriesByID[entryID]?.key ?? rightEntriesByID[entryID]?.key
        })
        differenceSummaryItems = Self.differenceSummaryItems(
            leftEntries: leftEntries,
            rightEntries: rightEntries
        )
        allSections = Self.sections(
            orderedEntryIDs: orderedEntryIDs,
            includedEntryIDs: Set(orderedEntryIDs),
            leftEntriesByID: leftEntriesByID,
            rightEntriesByID: rightEntriesByID
        )
        differingSections = Self.sections(
            orderedEntryIDs: orderedEntryIDs,
            includedEntryIDs: differingEntryIDs,
            leftEntriesByID: leftEntriesByID,
            rightEntriesByID: rightEntriesByID
        )
    }

    private init(
        differingMetadataKeys: Set<String>,
        differenceSummaryItems: [DifferenceSummaryItem],
        allSections: [ComparisonSection],
        differingSections: [ComparisonSection]
    ) {
        self.differingMetadataKeys = differingMetadataKeys
        self.differenceSummaryItems = differenceSummaryItems
        self.allSections = allSections
        self.differingSections = differingSections
    }

    func sections(showingOnlyDifferences: Bool) -> [ComparisonSection] {
        showingOnlyDifferences ? differingSections : allSections
    }

    private static func differenceSummaryItems(
        leftEntries: [MetadataComparisonEntry],
        rightEntries: [MetadataComparisonEntry]
    ) -> [DifferenceSummaryItem] {
        let leftValues = valuesByKey(leftEntries)
        let rightValues = valuesByKey(rightEntries)
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

    private static func sections(
        orderedEntryIDs: [String],
        includedEntryIDs: Set<String>,
        leftEntriesByID: [String: MetadataComparisonEntry],
        rightEntriesByID: [String: MetadataComparisonEntry]
    ) -> [ComparisonSection] {
        let includedEntries = orderedEntryIDs.compactMap { entryID -> MetadataComparisonEntry? in
            guard includedEntryIDs.contains(entryID) else {
                return nil
            }
            return leftEntriesByID[entryID] ?? rightEntriesByID[entryID]
        }
        let orderedSectionIDs = uniqueValues(includedEntries.map(\.sectionID))

        return orderedSectionIDs.compactMap { sectionID in
            let sectionEntries = includedEntries.filter { $0.sectionID == sectionID }
            guard let firstEntry = sectionEntries.first else {
                return nil
            }

            let rows = sectionEntries.map { entry in
                let leftValue = leftEntriesByID[entry.id]?.value ?? "-"
                let rightValue = rightEntriesByID[entry.id]?.value ?? "-"
                return ComparisonRow(
                    id: entry.id,
                    key: entry.key,
                    label: entry.label,
                    leftValue: leftValue,
                    rightValue: rightValue,
                    isDifferent: leftValue != rightValue
                )
            }

            return ComparisonSection(id: sectionID, title: firstEntry.sectionTitle, rows: rows)
        }
    }

    private static func comparisonEntries(for metadata: PhotoMetadata) -> [MetadataComparisonEntry] {
        var entries: [MetadataComparisonEntry] = []

        for section in metadata.sections {
            if section.itemGroups.isEmpty {
                entries.append(contentsOf: section.items.map {
                    comparisonEntry(item: $0, section: section, group: nil)
                })
            } else {
                for group in section.itemGroups {
                    entries.append(contentsOf: group.items.map {
                        comparisonEntry(item: $0, section: section, group: group)
                    })
                }
            }
        }

        if let coordinate = metadata.coordinate {
            let gpsSection = metadata.sections.first(where: isGPSSection)
            let sectionID = gpsSection?.id ?? "__location__"
            let sectionTitle = gpsSection?.title ?? "GPS"
            entries.append(MetadataComparisonEntry(
                id: "\(sectionID)|__coordinate__",
                sectionID: sectionID,
                sectionTitle: sectionTitle,
                key: "__coordinate__",
                label: AppLocalization.string("metadataShare.location"),
                value: LocationFormatter.coordinateText(coordinate)
            ))
        }

        return entries
    }

    private static func comparisonEntry(
        item: MetadataItem,
        section: MetadataSection,
        group: MetadataItemGroup?
    ) -> MetadataComparisonEntry {
        let groupID = group?.id ?? "__ungrouped__"
        let keyLabel = MetadataKeyTranslator.chineseName(for: item.key) ?? item.key
        let label = group.map { "\($0.title) · \(keyLabel)" } ?? keyLabel
        return MetadataComparisonEntry(
            id: "\(section.id)|\(groupID)|\(item.key)",
            sectionID: section.id,
            sectionTitle: section.title,
            key: item.key,
            label: label,
            value: item.value
        )
    }

    private static func entriesByID(_ entries: [MetadataComparisonEntry]) -> [String: MetadataComparisonEntry] {
        entries.reduce(into: [:]) { result, entry in
            result[entry.id] = entry
        }
    }

    private static func valuesByKey(_ entries: [MetadataComparisonEntry]) -> [String: String] {
        entries.reduce(into: [:]) { result, entry in
            if result[entry.key] == nil {
                result[entry.key] = entry.value
            }
        }
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        values.reduce(into: []) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    nonisolated private static func isGPSSection(_ section: MetadataSection) -> Bool {
        section.id.caseInsensitiveCompare(String(kCGImagePropertyGPSDictionary)) == .orderedSame ||
        section.title.caseInsensitiveCompare("GPS") == .orderedSame
    }
}

nonisolated private struct MetadataComparisonEntry: Sendable {
    let id: String
    let sectionID: String
    let sectionTitle: String
    let key: String
    let label: String
    let value: String
}

enum MacPhotoComparisonFeedback: Equatable {
    case copied
    case exported(URL)
    case exportFailed

    var message: String {
        switch self {
        case .copied:
            return AppLocalization.string("mac.comparison.copied")
        case .exported(let url):
            return AppLocalization.string("mac.comparison.exported", url.lastPathComponent)
        case .exportFailed:
            return AppLocalization.string("mac.comparison.exportFailed")
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

#endif
