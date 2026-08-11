#if os(macOS)

import SwiftUI

struct ComparisonRow: Identifiable, Equatable {
    let key: String
    let label: String
    let leftValue: String
    let rightValue: String
    let isDifferent: Bool

    var id: String { key }
}

struct ComparisonSection: Identifiable, Equatable {
    let title: String
    let rows: [ComparisonRow]

    var id: String { title }
}

struct DifferenceSummaryItem: Identifiable, Equatable {
    let key: String
    let label: String
    let leftValue: String
    let rightValue: String

    var id: String { key }
}

struct MacPhotoComparisonSnapshot: Equatable {
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
        let leftValues = Self.metadataValueMap(for: leftMetadata)
        let rightValues = Self.metadataValueMap(for: rightMetadata)
        let allKeys = Set(leftValues.keys).union(rightValues.keys)
        let differingKeys = Set(allKeys.filter { leftValues[$0] != rightValues[$0] })

        differingMetadataKeys = differingKeys
        differenceSummaryItems = Self.differenceSummaryItems(
            leftValues: leftValues,
            rightValues: rightValues
        )
        allSections = Self.sections(
            leftMetadata: leftMetadata,
            rightMetadata: rightMetadata,
            leftValues: leftValues,
            rightValues: rightValues,
            keys: allKeys
        )
        differingSections = Self.sections(
            leftMetadata: leftMetadata,
            rightMetadata: rightMetadata,
            leftValues: leftValues,
            rightValues: rightValues,
            keys: differingKeys
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

    private static func metadataValueMap(for metadata: PhotoMetadata) -> [String: String] {
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

    private static func differenceSummaryItems(
        leftValues: [String: String],
        rightValues: [String: String]
    ) -> [DifferenceSummaryItem] {
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
        leftMetadata: PhotoMetadata,
        rightMetadata: PhotoMetadata,
        leftValues: [String: String],
        rightValues: [String: String],
        keys: Set<String>
    ) -> [ComparisonSection] {
        let orderedTitles = leftMetadata.sections.map(\.title) + rightMetadata.sections.map(\.title)
        let uniqueTitles = orderedTitles.reduce(into: [String]()) { result, title in
            if !result.contains(title) {
                result.append(title)
            }
        }

        return uniqueTitles.compactMap { title in
            let leftSection = leftMetadata.sections.first(where: { $0.title == title })
            let rightSection = rightMetadata.sections.first(where: { $0.title == title })
            let orderedKeys = ((leftSection?.items ?? []) + (rightSection?.items ?? [])).map(\.key)
            let uniqueKeys = orderedKeys.reduce(into: [String]()) { result, key in
                if keys.contains(key), !result.contains(key) {
                    result.append(key)
                }
            }

            let rows = uniqueKeys.map { key in
                let leftValue = leftValues[key] ?? "-"
                let rightValue = rightValues[key] ?? "-"
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
