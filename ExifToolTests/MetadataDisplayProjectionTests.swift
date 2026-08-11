import CoreLocation
import XCTest
@testable import ExifTool

final class MetadataDisplayProjectionTests: XCTestCase {
    @MainActor
    func testFiltersDirectAndGroupedItemsIntoDisplayContent() throws {
        let metadata = PhotoMetadata(
            sections: [
                MetadataSection(
                    id: "camera",
                    title: "Camera",
                    items: [
                        MetadataItem(id: "make", key: "Make", value: "FUJIFILM"),
                        MetadataItem(id: "model", key: "Model", value: "X-T5")
                    ],
                    itemGroups: [
                        MetadataItemGroup(
                            id: "exposure",
                            title: "Exposure",
                            items: [
                                MetadataItem(id: "focus", key: "FocusMode", value: "Auto"),
                                MetadataItem(id: "iso", key: "ISOSpeedRatings", value: "400")
                            ]
                        )
                    ]
                ),
                MetadataSection(
                    id: "unused",
                    title: "Unused",
                    items: [MetadataItem(id: "artist", key: "Artist", value: "A")]
                )
            ],
            coordinate: nil
        )

        let projection = MetadataDisplayProjection(
            metadata: metadata,
            showsChineseKeys: true,
            highlightedMetadataKeys: ["FocusMode"],
            visibleMetadataKeys: ["Model", "FocusMode"]
        )

        let section = try XCTUnwrap(projection.sections.first)
        XCTAssertEqual(projection.sections.map(\.id), ["camera"])
        XCTAssertEqual(section.items.map(\.key), ["Model"])
        XCTAssertEqual(section.items.first?.title, "设备型号")

        let groupedItem = try XCTUnwrap(section.itemGroups.first?.items.first)
        XCTAssertEqual(groupedItem.key, "FocusMode")
        XCTAssertEqual(groupedItem.value, "自动")
        XCTAssertTrue(groupedItem.isHighlighted)
    }

    @MainActor
    func testOrdersCameraParameterSectionsFirstAndPreservesRelativeOrder() {
        let metadata = PhotoMetadata(
            sections: [
                section(id: "tiff"),
                section(id: "sony-parameters"),
                section(id: "exif"),
                section(id: "fujifilm-parameters"),
                section(id: "nikon-parameters")
            ],
            coordinate: nil
        )

        let projection = MetadataDisplayProjection(metadata: metadata, showsChineseKeys: false)

        XCTAssertEqual(
            projection.sections.map(\.id),
            ["sony-parameters", "fujifilm-parameters", "nikon-parameters", "tiff", "exif"]
        )
    }

    @MainActor
    func testMarksLocationSectionAndFallsBackToFirstSelection() throws {
        let coordinate = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        let metadata = PhotoMetadata(
            sections: [
                MetadataSection(
                    id: "{GPS}",
                    title: "GPS",
                    items: [MetadataItem(id: "latitude", key: "GPSLatitude", value: "31.2304")]
                )
            ],
            coordinate: coordinate
        )
        let projection = MetadataDisplayProjection(metadata: metadata, showsChineseKeys: false)

        XCTAssertTrue(try XCTUnwrap(projection.sections.first).isLocationSection)
        XCTAssertEqual(projection.selectedSection(id: "missing")?.id, "{GPS}")
        XCTAssertEqual(projection.coordinate?.latitude, coordinate.latitude)
        XCTAssertEqual(projection.coordinate?.longitude, coordinate.longitude)
    }

    private func section(id: String) -> MetadataSection {
        MetadataSection(
            id: id,
            title: id,
            items: [MetadataItem(id: "\(id)-item", key: "Model", value: id)]
        )
    }
}
