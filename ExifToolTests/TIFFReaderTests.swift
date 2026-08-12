#if os(macOS)

import XCTest
@testable import ExifTool

final class TIFFReaderTests: XCTestCase {
    func testReadsIntegerValuesInBothByteOrders() {
        let data = Data([0x01, 0x02, 0x03, 0x04])

        XCTAssertEqual(TIFFReader(data: data, byteOrder: .little).uint16(at: 0), 0x0201)
        XCTAssertEqual(TIFFReader(data: data, byteOrder: .big).uint16(at: 0), 0x0102)
        XCTAssertEqual(TIFFReader(data: data, byteOrder: .little).uint32(at: 0), 0x04030201)
        XCTAssertEqual(TIFFReader(data: data, byteOrder: .big).uint32(at: 0), 0x01020304)
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
