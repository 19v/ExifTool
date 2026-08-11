#if os(macOS)

import CoreLocation
import ImageIO
import SwiftUI

struct MacPhotoMetadataContent: View {
    let metadata: PhotoMetadata
    let showsChineseKeys: Bool
    let highlightedMetadataKeys: Set<String>
    let visibleMetadataKeys: Set<String>?

    @Environment(\.openURL) private var openURL
    @State private var selectedSectionID: String?
    @State private var mapCoordinate: CLLocationCoordinate2D?
    @State private var isMapChooserPresented = false

    private var filteredSections: [MetadataSection] {
        let sections: [MetadataSection]

        if let visibleMetadataKeys {
            sections = metadata.sections.compactMap { section in
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
        } else {
            sections = metadata.sections
        }

        return sections
            .enumerated()
            .sorted { lhs, rhs in
                let lhsPriority = specialSectionPriority(for: lhs.element)
                let rhsPriority = specialSectionPriority(for: rhs.element)
                return lhsPriority == rhsPriority ? lhs.offset < rhs.offset : lhsPriority < rhsPriority
            }
            .map(\.element)
    }

    private var selectedSection: MetadataSection? {
        guard let selectedSectionID,
              let selectedSection = filteredSections.first(where: { $0.id == selectedSectionID }) else {
            return filteredSections.first
        }

        return selectedSection
    }

    private var sectionSelectionSignature: String {
        filteredSections.map(\.id).joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !filteredSections.isEmpty {
                MacMetadataSectionPicker(
                    sections: filteredSections,
                    selectedSectionID: selectedSection?.id,
                    showsChineseKeys: showsChineseKeys,
                    onSelect: selectSection
                )
            }

            if filteredSections.isEmpty {
                ContentUnavailableView("没有 Exif 信息", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let selectedSection {
                if let coordinate = metadata.coordinate, isGPSSection(selectedSection) {
                    MacMetadataLocationButton(coordinate: coordinate) {
                        mapCoordinate = coordinate
                        isMapChooserPresented = true
                    }
                }

                MacMetadataSectionView(
                    section: selectedSection,
                    showsChineseKeys: showsChineseKeys,
                    highlightedMetadataKeys: highlightedMetadataKeys
                )
            }
        }
        .onAppear(perform: updateSelection)
        .onChange(of: sectionSelectionSignature) {
            updateSelection()
        }
        .confirmationDialog("选择地图", isPresented: $isMapChooserPresented, titleVisibility: .visible) {
            if let mapCoordinate {
                Button("系统地图") { openURL(MapDestination.appleMaps.url(for: mapCoordinate)) }
                Button("高德地图") { openURL(MapDestination.amap.url(for: mapCoordinate)) }
                Button("Google Maps") { openURL(MapDestination.googleMaps.url(for: mapCoordinate)) }
            }
            Button("取消", role: .cancel) { }
        }
    }

    private func selectSection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSectionID = id
        }
    }

    private func updateSelection() {
        guard selectedSection?.id != selectedSectionID else {
            return
        }

        selectedSectionID = filteredSections.first?.id
    }

    private func isGPSSection(_ section: MetadataSection) -> Bool {
        section.id.caseInsensitiveCompare(String(kCGImagePropertyGPSDictionary)) == .orderedSame ||
        section.title.caseInsensitiveCompare("GPS") == .orderedSame
    }

    private func specialSectionPriority(for section: MetadataSection) -> Int {
        switch section.id {
        case "fujifilm-parameters", "nikon-parameters":
            return 0
        default:
            return 1
        }
    }
}

private struct MacMetadataSectionPicker: View {
    let sections: [MetadataSection]
    let selectedSectionID: String?
    let showsChineseKeys: Bool
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections) { section in
                    let isSelected = section.id == selectedSectionID
                    Button {
                        onSelect(section.id)
                    } label: {
                        Text(MetadataDisplayLocalizer.sectionTitle(section, showsChinese: showsChineseKeys))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(
                                isSelected ? Color.accentColor : Color.platformSecondaryBackground,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityLabel("参数分类")
    }
}

private struct MacMetadataLocationButton: View {
    let coordinate: CLLocationCoordinate2D
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "map")
                VStack(alignment: .leading, spacing: 3) {
                    Text("地理位置")
                        .font(.headline)
                    Text(LocationFormatter.coordinateText(coordinate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.platformSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityHint("选择地图应用打开这个位置")
    }
}

#endif
