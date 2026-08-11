#if os(macOS)

import CoreLocation
import XCTest
@testable import ExifTool

final class MacPhotoComparisonSnapshotTests: XCTestCase {
    func testGroupedMakerNoteItemParticipatesInDifferences() throws {
        let leftMetadata = metadataWithGroupedItem(value: "AF-S")
        let rightMetadata = metadataWithGroupedItem(value: "AF-C")

        let snapshot = MacPhotoComparisonSnapshot(
            leftMetadata: leftMetadata,
            rightMetadata: rightMetadata
        )

        XCTAssertTrue(snapshot.differingMetadataKeys.contains("FocusMode"))
        let section = try XCTUnwrap(snapshot.differingSections.first { $0.id == "sony-parameters" })
        let row = try XCTUnwrap(section.rows.first { $0.key == "FocusMode" })
        XCTAssertEqual(row.leftValue, "AF-S")
        XCTAssertEqual(row.rightValue, "AF-C")
        XCTAssertTrue(row.label.contains("曝光"))
    }

    func testCoordinateDifferenceCreatesComparisonRow() throws {
        let leftMetadata = PhotoMetadata(
            sections: [],
            coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        )
        let rightMetadata = PhotoMetadata(
            sections: [],
            coordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        )

        let snapshot = MacPhotoComparisonSnapshot(
            leftMetadata: leftMetadata,
            rightMetadata: rightMetadata
        )

        XCTAssertTrue(snapshot.differingMetadataKeys.contains("__coordinate__"))
        let locationRow = try XCTUnwrap(
            snapshot.differingSections.flatMap(\.rows).first { $0.key == "__coordinate__" }
        )
        XCTAssertNotEqual(locationRow.leftValue, locationRow.rightValue)
    }

    private func metadataWithGroupedItem(value: String) -> PhotoMetadata {
        PhotoMetadata(
            sections: [
                MetadataSection(
                    id: "sony-parameters",
                    title: "SONY 参数",
                    items: [],
                    itemGroups: [
                        MetadataItemGroup(
                            id: "exposure",
                            title: "曝光",
                            items: [
                                MetadataItem(
                                    id: "focus-mode",
                                    key: "FocusMode",
                                    value: value
                                )
                            ]
                        )
                    ]
                )
            ],
            coordinate: nil
        )
    }
}

#endif
