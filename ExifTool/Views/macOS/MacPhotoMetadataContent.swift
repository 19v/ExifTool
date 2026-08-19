#if os(macOS)

import CoreLocation
import SwiftUI

struct MacPhotoMetadataContent: View {
    let previewImage: PlatformImage?
    private let projection: MetadataDisplayProjection

    @Environment(\.openURL) private var openURL
    @State private var mapCoordinate: CLLocationCoordinate2D?
    @State private var isMapChooserPresented = false

    init(
        previewImage: PlatformImage?,
        metadata: PhotoMetadata,
        showsChineseKeys: Bool,
        highlightedMetadataKeys: Set<String>,
        visibleMetadataKeys: Set<String>?
    ) {
        self.previewImage = previewImage
        let projection = MetadataDisplayProjection(
            metadata: metadata,
            showsChineseKeys: showsChineseKeys,
            highlightedMetadataKeys: highlightedMetadataKeys,
            visibleMetadataKeys: visibleMetadataKeys
        )
        self.projection = projection
    }

    var body: some View {
        List {
            Section {
                MacPhotoPreview(image: previewImage)
            }

            if projection.listSections.isEmpty {
                ContentUnavailableView("没有 Exif 信息", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(projection.listSections) { section in
                    Section(section.title) {
                        if section.showsLocationAction, let coordinate = projection.coordinate {
                            MacMetadataLocationButton(coordinate: coordinate) {
                                mapCoordinate = coordinate
                                isMapChooserPresented = true
                            }
                        }

                        ForEach(section.items) { item in
                            MacMetadataItemRow(item: item)
                        }
                    }
                }
            }
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
}

private struct MacMetadataItemRow: View {
    let item: MetadataDisplayItem

    var body: some View {
        LabeledContent {
            Text(item.value)
                .textSelection(.enabled)
        } label: {
            Text(item.title)
        }
        .listRowBackground(item.isHighlighted ? Color.accentColor.opacity(0.12) : nil)
    }
}

private struct MacMetadataLocationButton: View {
    let coordinate: CLLocationCoordinate2D
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledContent {
                Text(LocationFormatter.coordinateText(coordinate))
            } label: {
                Label("在地图中打开", systemImage: "map")
            }
        }
        .accessibilityHint("选择地图应用打开这个位置")
    }
}

#endif
