//
//  MetadataDisplayProjection.swift
//  ExifTool
//
//  Projects parsed metadata into display-ready, consistently ordered content.
//

import CoreLocation
import ImageIO

struct MetadataDisplayProjection {
    let sections: [MetadataDisplaySection]
    let coordinate: CLLocationCoordinate2D?

    var sectionIDs: [String] {
        sections.map(\.id)
    }

    init(
        metadata: PhotoMetadata,
        showsChineseKeys: Bool,
        highlightedMetadataKeys: Set<String> = [],
        visibleMetadataKeys: Set<String>? = nil
    ) {
        coordinate = metadata.coordinate
        sections = Self.filteredAndOrderedSections(
            metadata.sections,
            visibleMetadataKeys: visibleMetadataKeys
        ).map { section in
            MetadataDisplaySection(
                section: section,
                showsChineseKeys: showsChineseKeys,
                highlightedMetadataKeys: highlightedMetadataKeys
            )
        }
    }

    func selectedSection(id: String?) -> MetadataDisplaySection? {
        guard let id,
              let section = sections.first(where: { $0.id == id }) else {
            return sections.first
        }
        return section
    }

    private static func filteredAndOrderedSections(
        _ sections: [MetadataSection],
        visibleMetadataKeys: Set<String>?
    ) -> [MetadataSection] {
        let filteredSections: [MetadataSection]
        if let visibleMetadataKeys {
            filteredSections = sections.compactMap { section in
                filteredSection(section, visibleMetadataKeys: visibleMetadataKeys)
            }
        } else {
            filteredSections = sections
        }

        return filteredSections
            .enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = specialSectionPriority(for: lhs.element)
                let rhsPriority = specialSectionPriority(for: rhs.element)
                return lhsPriority == rhsPriority ? lhs.offset < rhs.offset : lhsPriority < rhsPriority
            }
            .map(\.element)
    }

    private static func filteredSection(
        _ section: MetadataSection,
        visibleMetadataKeys: Set<String>
    ) -> MetadataSection? {
        let items = section.items.filter { visibleMetadataKeys.contains($0.key) }
        let itemGroups = section.itemGroups.compactMap { group -> MetadataItemGroup? in
            let groupItems = group.items.filter { visibleMetadataKeys.contains($0.key) }
            guard !groupItems.isEmpty else {
                return nil
            }
            return MetadataItemGroup(id: group.id, title: group.title, items: groupItems)
        }

        guard !items.isEmpty || !itemGroups.isEmpty else {
            return nil
        }
        return MetadataSection(id: section.id, title: section.title, items: items, itemGroups: itemGroups)
    }

    private static func specialSectionPriority(for section: MetadataSection) -> Int {
        switch section.id {
        case "fujifilm-parameters", "nikon-parameters", "sony-parameters":
            return 0
        default:
            return 1
        }
    }
}

struct MetadataDisplaySection: Identifiable {
    let id: String
    let title: String
    let items: [MetadataDisplayItem]
    let itemGroups: [MetadataDisplayItemGroup]
    let isLocationSection: Bool

    init(
        section: MetadataSection,
        showsChineseKeys: Bool,
        highlightedMetadataKeys: Set<String>
    ) {
        id = section.id
        title = MetadataDisplayLocalizer.sectionTitle(section, showsChinese: showsChineseKeys)
        items = section.items.map {
            MetadataDisplayItem(
                item: $0,
                showsChineseKeys: showsChineseKeys,
                highlightedMetadataKeys: highlightedMetadataKeys
            )
        }
        itemGroups = section.itemGroups.map {
            MetadataDisplayItemGroup(
                group: $0,
                showsChineseKeys: showsChineseKeys,
                highlightedMetadataKeys: highlightedMetadataKeys
            )
        }
        isLocationSection = section.id.caseInsensitiveCompare(String(kCGImagePropertyGPSDictionary)) == .orderedSame ||
            section.title.caseInsensitiveCompare("GPS") == .orderedSame
    }
}

struct MetadataDisplayItemGroup: Identifiable {
    let id: String
    let title: String
    let items: [MetadataDisplayItem]

    init(
        group: MetadataItemGroup,
        showsChineseKeys: Bool,
        highlightedMetadataKeys: Set<String>
    ) {
        id = group.id
        title = MetadataDisplayLocalizer.sectionTitle(
            MetadataSection(id: group.id, title: group.title, items: group.items),
            showsChinese: showsChineseKeys
        )
        items = group.items.map {
            MetadataDisplayItem(
                item: $0,
                showsChineseKeys: showsChineseKeys,
                highlightedMetadataKeys: highlightedMetadataKeys
            )
        }
    }
}

struct MetadataDisplayItem: Identifiable {
    let id: String
    let key: String
    let title: String
    let value: String
    let isHighlighted: Bool

    init(
        item: MetadataItem,
        showsChineseKeys: Bool,
        highlightedMetadataKeys: Set<String>
    ) {
        id = item.id
        key = item.key
        title = MetadataDisplayLocalizer.keyTitle(item.key, showsChinese: showsChineseKeys)
        value = MetadataDisplayLocalizer.valueText(item.value, showsChinese: showsChineseKeys)
        isHighlighted = highlightedMetadataKeys.contains(item.key)
    }
}
