#if os(iOS)

import CoreLocation
import SwiftUI

struct IOSPhotoMetadataContent: View {
    let previewImage: PlatformImage?
    private let projection: MetadataDisplayProjection
    let photoNavigation: PhotoNavigationConfiguration?

    @Environment(\.openURL) private var openURL
    @State private var mapCoordinate: CLLocationCoordinate2D?
    @State private var isMapChooserPresented = false

    init(
        previewImage: PlatformImage?,
        metadata: PhotoMetadata,
        showsChineseKeys: Bool,
        photoNavigation: PhotoNavigationConfiguration?,
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
        self.photoNavigation = photoNavigation
    }

    var body: some View {
        List {
            Section {
                IOSPhotoDetailPreview(
                    image: previewImage,
                    photoNavigation: photoNavigation
                )
            }

            if projection.listSections.isEmpty {
                ContentUnavailableView("没有 Exif 信息", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ForEach(projection.listSections) { section in
                    Section(section.title) {
                        if section.showsLocationAction, let coordinate = projection.coordinate {
                            MetadataLocationButton(coordinate: coordinate) {
                                mapCoordinate = coordinate
                                isMapChooserPresented = true
                            }
                        }

                        ForEach(section.items) { item in
                            MetadataItemRow(item: item)
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

struct IOSPhotoDetailPreview: View {
    let image: PlatformImage?
    let photoNavigation: PhotoNavigationConfiguration?

    var body: some View {
        PhotoPreview(image: image)
            .simultaneousGesture(photoSwipeGesture)
    }

    private var photoSwipeGesture: some Gesture {
        DragGesture(minimumDistance: PhotoSwipeClassifier.minimumDistance)
            .onEnded { value in
                guard let photoNavigation,
                      let direction = PhotoSwipeClassifier.direction(
                          translation: value.translation,
                          predictedEndTranslation: value.predictedEndTranslation
                      ) else {
                    return
                }

                switch direction {
                case .previous where photoNavigation.canSelectPrevious:
                    photoNavigation.selectPrevious()
                case .next where photoNavigation.canSelectNext:
                    photoNavigation.selectNext()
                case .previous, .next:
                    break
                }
            }
    }
}

private struct MetadataItemRow: View {
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

private struct MetadataLocationButton: View {
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
