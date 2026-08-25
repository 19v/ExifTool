#if os(macOS)

import XCTest
@testable import ExifTool

final class TIFFReaderTests: XCTestCase {
    func testSharedIFDDecoderReadsInlineAndOffsetValues() {
        let data = Data([
            0x02, 0x00,
            0x21, 0x10, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
            0x23, 0x10, 0x03, 0x00, 0x03, 0x00, 0x00, 0x00, 0x1e, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x0a, 0x00, 0x14, 0x00, 0x1e, 0x00
        ])

        let entries = TIFFIFDDecoder.entries(
            in: data,
            ifdOffset: 0,
            byteOrder: .little,
            valueOffsetBases: [0]
        )

        XCTAssertEqual(entries.map(\.tag), [0x1021, 0x1023])
        XCTAssertEqual(entries[0].valueData, Data([0x01, 0x00]))
        XCTAssertEqual(entries[1].valueData, Data([0x0a, 0x00, 0x14, 0x00, 0x1e, 0x00]))
    }

    func testReadsIntegerValuesInBothByteOrders() {
        let data = Data([0x01, 0x02, 0x03, 0x04])

        XCTAssertEqual(TIFFReader(data: data, byteOrder: .little).uint16(at: 0), 0x0201)
        XCTAssertEqual(TIFFReader(data: data, byteOrder: .big).uint16(at: 0), 0x0102)
        XCTAssertEqual(TIFFReader(data: data, byteOrder: .little).uint32(at: 0), 0x04030201)
        XCTAssertEqual(TIFFReader(data: data, byteOrder: .big).uint32(at: 0), 0x01020304)
    }

    func testIFDDecoderTriesOffsetBasesInOrder() {
        var data = Data(repeating: 0, count: 48)
        data[0] = 0x01
        data.replaceSubrange(2..<14, with: [
            0x01, 0x20, 0x03, 0x00, 0x03, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00
        ])
        data.replaceSubrange(32..<38, with: [0x0a, 0x00, 0x14, 0x00, 0x1e, 0x00])

        let entries = TIFFIFDDecoder.entries(
            in: data,
            ifdOffset: 0,
            byteOrder: .little,
            valueOffsetBases: [1_000, 16]
        )

        XCTAssertEqual(entries.first?.valueData, Data([0x0a, 0x00, 0x14, 0x00, 0x1e, 0x00]))
    }

    func testIFDDecoderRejectsUnsupportedTypesAndExcessiveCounts() {
        let unsupportedType = Data([
            0x01, 0x00,
            0x01, 0x20, 0xff, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00
        ])
        let excessiveCount = Data([
            0x01, 0x00,
            0x01, 0x20, 0x01, 0x00, 0x01, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])

        XCTAssertTrue(TIFFIFDDecoder.entries(
            in: unsupportedType,
            ifdOffset: 0,
            byteOrder: .little,
            valueOffsetBases: [0]
        ).isEmpty)
        XCTAssertTrue(TIFFIFDDecoder.entries(
            in: excessiveCount,
            ifdOffset: 0,
            byteOrder: .little,
            valueOffsetBases: [0]
        ).isEmpty)
    }

    func testRejectsNegativeTruncatedAndOverflowingRanges() {
        let reader = TIFFReader(data: Data([0, 1, 2, 3]), byteOrder: .little)

        XCTAssertNil(reader.uint16(at: -1))
        XCTAssertNil(reader.uint32(at: 1))
        XCTAssertNil(reader.bytes(at: Int.max, count: 2))
        XCTAssertNil(reader.bytes(at: 0, count: Int.max))
        XCTAssertNil(TIFFReader.offset(base: Int.max, relative: 1))
        XCTAssertNil(TIFFReader.offset(base: 0, relative: -1))
        XCTAssertNil(TIFFReader.byteCount(typeSize: Int.max, count: 2))
        XCTAssertNil(TIFFReader.byteCount(typeSize: 0, count: 1))
    }

    func testRandomInputsNeverProduceOutOfBoundsSlicesOrCrashVendorParsers() {
        var generator = DeterministicGenerator(state: 0x4558_4946_544f_4f4c)

        for _ in 0..<2_000 {
            let length = Int(generator.next() % 257)
            let data = Data((0..<length).map { _ in UInt8(truncatingIfNeeded: generator.next()) })

            for byteOrder in [TIFFByteOrder.little, .big] {
                let reader = TIFFReader(data: data, byteOrder: byteOrder)
                let offsetCandidates = [-1, 0, length / 2, length, Int.max]
                for offset in offsetCandidates {
                    _ = reader.uint16(at: offset)
                    _ = reader.uint32(at: offset)
                    if let bytes = reader.bytes(at: offset, count: Int(generator.next() % 32)) {
                        XCTAssertLessThanOrEqual(bytes.count, data.count)
                    }
                }
            }

            _ = FujifilmMakerNoteParser.parse(data)
            _ = SonyMakerNoteParser.parse(data)
            _ = NikonMakerNoteParser.parse(data)
            _ = AppleMakerNoteParser.parse(data)
        }
    }

    func testMakerNoteMutationPerformance() {
        var generator = DeterministicGenerator(state: 0x5045_5246_5445_5354)
        let samples = (0..<1_000).map { _ in
            Data((0..<256).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
        }

        measure {
            for data in samples {
                _ = FujifilmMakerNoteParser.parse(data)
                _ = NikonMakerNoteParser.parse(data)
                _ = SonyMakerNoteParser.parse(data)
                _ = AppleMakerNoteParser.parse(data)
            }
        }
    }
}

private struct DeterministicGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

#endif
