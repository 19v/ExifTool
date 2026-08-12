#if os(macOS)

import ImageIO
import XCTest
@testable import ExifTool

final class MakerNoteParserTests: XCTestCase {
    @MainActor
    func testRealCameraFixturesProduceVendorSections() throws {
        let fixtures = [
            (fileName: "Fujifilm_FinePix_E500", sectionID: "fujifilm-parameters"),
            (fileName: "Nikon_D70", sectionID: "nikon-parameters"),
            (fileName: "Sony_HDR-HC3", sectionID: "sony-parameters")
        ]

        for fixture in fixtures {
            let url = try XCTUnwrap(
                Bundle(for: Self.self).url(forResource: fixture.fileName, withExtension: "jpg"),
                "Missing fixture \(fixture.fileName)"
            )
            let metadata = MetadataParser.parse(url: url, fallbackCoordinate: nil)
            let vendorSection = try XCTUnwrap(
                metadata.sections.first { $0.id == fixture.sectionID },
                "Expected vendor section for \(fixture.fileName)"
            )
            XCTAssertFalse(vendorSection.items.isEmpty, "Expected decoded fields for \(fixture.fileName)")
        }
    }

    @MainActor
    func testReducedRAWFixturesMatchPinnedExifToolCameraMetadata() throws {
        let fixtures = [
            (fileName: "Nikon_D70", extension: "nef", sectionID: "nikon-parameters", make: "NIKON CORPORATION", model: "NIKON D70")
        ]

        for fixture in fixtures {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: fixture.fileName, withExtension: fixture.extension))
            let metadata = MetadataParser.parse(url: url, fallbackCoordinate: nil)
            let flattenedItems = metadata.sections.flatMap(\.items)

            XCTAssertTrue(flattenedItems.contains { $0.value == fixture.make }, "Expected make for \(fixture.fileName)")
            XCTAssertTrue(flattenedItems.contains { $0.value == fixture.model }, "Expected model for \(fixture.fileName)")
            XCTAssertNotNil(
                metadata.sections.first { $0.id == fixture.sectionID },
                "Expected vendor MakerNote section for \(fixture.fileName)"
            )
        }
    }

    @MainActor
    func testReducedRAFFixtureFailsSafelyWhenImageIODoesNotExposeMetadata() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "Fujifilm_FinePix_S5Pro", withExtension: "raf")
        )

        let metadata = MetadataParser.parse(url: url, fallbackCoordinate: nil)

        XCTAssertTrue(metadata.sections.isEmpty)
        XCTAssertNil(metadata.coordinate)
    }

    func testFujifilmParsesLittleEndianInlineValue() {
        let data = makeIFD(
            endian: .little,
            entries: [IFDEntry(tag: 0x1021, type: 3, count: 1, inlineValue: 1)]
        )

        let fields = FujifilmMakerNoteParser.parse(data)

        XCTAssertEqual(fields["对焦模式"], "Manual")
    }

    func testSonyParsesBigEndianInlineValue() {
        let data = makeIFD(
            endian: .big,
            entries: [IFDEntry(tag: 0x201b, type: 3, count: 1, inlineValue: 1)]
        )

        let fields = SonyMakerNoteParser.parse(data)

        XCTAssertEqual(fields["对焦模式"], "AF-S")
    }

    func testNikonParsesTIFFWrappedShutterCount() {
        let data = makeTIFF(
            endian: .little,
            entries: [IFDEntry(tag: 0x00a7, type: 4, count: 1, inlineValue: 12_345)]
        )

        let fields = NikonMakerNoteParser.parse(data)

        XCTAssertEqual(fields["快门次数"], "12345")
    }

    @MainActor
    func testCameraMetadataBuilderRoutesVendorMakerNotes() throws {
        let fixtures: [(make: String, makerNote: Data, sectionID: String, key: String, value: String)] = [
            (
                "FUJIFILM",
                makeIFD(
                    endian: .little,
                    entries: [IFDEntry(tag: 0x1021, type: 3, count: 1, inlineValue: 1)]
                ),
                "fujifilm-parameters",
                "对焦模式",
                "Manual"
            ),
            (
                "SONY",
                makeIFD(
                    endian: .big,
                    entries: [IFDEntry(tag: 0x201b, type: 3, count: 1, inlineValue: 1)]
                ),
                "sony-parameters",
                "对焦模式",
                "AF-S"
            ),
            (
                "NIKON",
                makeTIFF(
                    endian: .little,
                    entries: [IFDEntry(tag: 0x00a7, type: 4, count: 1, inlineValue: 12_345)]
                ),
                "nikon-parameters",
                "快门次数",
                "12345"
            )
        ]

        for fixture in fixtures {
            let properties: [String: Any] = [
                String(kCGImagePropertyTIFFDictionary): [
                    String(kCGImagePropertyTIFFMake): fixture.make
                ],
                String(kCGImagePropertyExifDictionary): [
                    String(kCGImagePropertyExifMakerNote): fixture.makerNote
                ]
            ]

            let sections = CameraMetadataSectionBuilder.sections(from: properties)
            let section = try XCTUnwrap(
                sections.first { $0.id == fixture.sectionID },
                "Expected section for \(fixture.make)"
            )
            let item = try XCTUnwrap(
                section.items.first { $0.key == fixture.key },
                "Expected \(fixture.key) for \(fixture.make)"
            )
            XCTAssertEqual(item.value, fixture.value)
        }
    }

    func testTruncatedMakerNotesReturnNoFields() {
        let truncatedSamples = [
            Data(),
            Data([0x49]),
            Data([0x49, 0x49, 0x2a]),
            Data([0x01, 0x00, 0x21, 0x10])
        ]

        for data in truncatedSamples {
            XCTAssertTrue(FujifilmMakerNoteParser.parse(data).isEmpty)
            XCTAssertTrue(SonyMakerNoteParser.parse(data).isEmpty)
            XCTAssertTrue(NikonMakerNoteParser.parse(data).isEmpty)
        }
    }

    func testOutOfRangeValueOffsetsAreIgnored() {
        let invalidEntry = IFDEntry(
            tag: 0x1023,
            type: 3,
            count: 3,
            inlineValue: UInt32.max
        )
        let data = makeIFD(endian: .little, entries: [invalidEntry])

        XCTAssertTrue(FujifilmMakerNoteParser.parse(data).isEmpty)
        XCTAssertTrue(SonyMakerNoteParser.parse(data).isEmpty)
    }
}

private extension MakerNoteParserTests {
    enum Endian {
        case little
        case big
    }

    struct IFDEntry {
        let tag: UInt16
        let type: UInt16
        let count: UInt32
        let inlineValue: UInt32
    }

    func makeTIFF(endian: Endian, entries: [IFDEntry]) -> Data {
        var data = Data()
        switch endian {
        case .little:
            data.append(contentsOf: [0x49, 0x49, 0x2a, 0x00])
        case .big:
            data.append(contentsOf: [0x4d, 0x4d, 0x00, 0x2a])
        }
        append(UInt32(8), endian: endian, to: &data)
        data.append(makeIFD(endian: endian, entries: entries))
        return data
    }

    func makeIFD(endian: Endian, entries: [IFDEntry]) -> Data {
        var data = Data()
        append(UInt16(entries.count), endian: endian, to: &data)

        for entry in entries {
            append(entry.tag, endian: endian, to: &data)
            append(entry.type, endian: endian, to: &data)
            append(entry.count, endian: endian, to: &data)
            if entry.type == 3, entry.count == 1 {
                append(UInt16(truncatingIfNeeded: entry.inlineValue), endian: endian, to: &data)
                append(UInt16(0), endian: endian, to: &data)
            } else {
                append(entry.inlineValue, endian: endian, to: &data)
            }
        }

        return data
    }

    func append(_ value: UInt16, endian: Endian, to data: inout Data) {
        let bytes: [UInt8]
        switch endian {
        case .little:
            bytes = [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
        case .big:
            bytes = [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        }
        data.append(contentsOf: bytes)
    }

    func append(_ value: UInt32, endian: Endian, to data: inout Data) {
        let bytes: [UInt8]
        switch endian {
        case .little:
            bytes = [
                UInt8(truncatingIfNeeded: value),
                UInt8(truncatingIfNeeded: value >> 8),
                UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 24)
            ]
        case .big:
            bytes = [
                UInt8(truncatingIfNeeded: value >> 24),
                UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 8),
                UInt8(truncatingIfNeeded: value)
            ]
        }
        data.append(contentsOf: bytes)
    }
}

#endif
