#if os(iOS)

import CoreLocation
import SwiftUI

struct IOSPhotoMetadataContent: View {
    private let projection: MetadataDisplayProjection

    @Environment(\.openURL) private var openURL
    @State private var selectedSectionID: String?
    @State private var mapCoordinate: CLLocationCoordinate2D?
    @State private var isMapChooserPresented = false

    init(
        metadata: PhotoMetadata,
        showsChineseKeys: Bool,
        highlightedMetadataKeys: Set<String>,
        visibleMetadataKeys: Set<String>?
    ) {
        projection = MetadataDisplayProjection(
            metadata: metadata,
            showsChineseKeys: showsChineseKeys,
            highlightedMetadataKeys: highlightedMetadataKeys,
            visibleMetadataKeys: visibleMetadataKeys
        )
    }

    private var selectedSection: MetadataDisplaySection? {
        projection.selectedSection(id: selectedSectionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !projection.sections.isEmpty {
                IOSMetadataSectionPicker(
                    sections: projection.sections,
                    selectedSectionID: selectedSection?.id,
                    onSelect: selectSection
                )
            }

            if projection.sections.isEmpty {
                ContentUnavailableView("没有 Exif 信息", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let selectedSection {
                if let coordinate = projection.coordinate, selectedSection.isLocationSection {
                    MetadataLocationButton(coordinate: coordinate) {
                        mapCoordinate = coordinate
                        isMapChooserPresented = true
                    }
                }

                MetadataSectionView(
                    section: selectedSection
                )
            }
        }
        .onAppear(perform: updateSelection)
        .onChange(of: projection.sectionIDs) {
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

        selectedSectionID = projection.sections.first?.id
    }
}

private struct IOSMetadataSectionPicker: View {
    let sections: [MetadataDisplaySection]
    let selectedSectionID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections) { section in
                    let isSelected = section.id == selectedSectionID
                    Button {
                        onSelect(section.id)
                    } label: {
                        Text(section.title)
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

private struct MetadataLocationButton: View {
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
