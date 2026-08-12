//
//  TIFFReader.swift
//  ExifTool
//
//  Shared, overflow-safe primitives for TIFF and MakerNote parsing.
//

import Foundation

nonisolated enum TIFFByteOrder: Sendable {
    case little
    case big
}

nonisolated struct TIFFReader: Sendable {
    let data: Data
    let byteOrder: TIFFByteOrder

    func uint16(at offset: Int) -> UInt16? {
        guard let range = Self.validRange(offset: offset, length: 2, dataCount: data.count) else {
            return nil
        }

        let first = UInt16(data[range.lowerBound])
        let second = UInt16(data[range.lowerBound + 1])
        switch byteOrder {
        case .little:
            return first | (second << 8)
        case .big:
            return (first << 8) | second
        }
    }

    func int16(at offset: Int) -> Int16? {
        uint16(at: offset).map(Int16.init(bitPattern:))
    }

    func uint32(at offset: Int) -> UInt32? {
        guard let range = Self.validRange(offset: offset, length: 4, dataCount: data.count) else {
            return nil
        }

        let b0 = UInt32(data[range.lowerBound])
        let b1 = UInt32(data[range.lowerBound + 1])
        let b2 = UInt32(data[range.lowerBound + 2])
        let b3 = UInt32(data[range.lowerBound + 3])
        switch byteOrder {
        case .little:
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        case .big:
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
    }

    func int32(at offset: Int) -> Int32? {
        uint32(at: offset).map(Int32.init(bitPattern:))
    }

    func bytes(at offset: Int, count: Int) -> Data? {
        guard let range = Self.validRange(offset: offset, length: count, dataCount: data.count) else {
            return nil
        }
        return data.subdata(in: range)
    }

    static func byteCount(typeSize: Int, count: Int) -> Int? {
        guard typeSize > 0, count > 0 else {
            return nil
        }
        let result = typeSize.multipliedReportingOverflow(by: count)
        return result.overflow ? nil : result.partialValue
    }

    static func offset(base: Int, relative: Int) -> Int? {
        let result = base.addingReportingOverflow(relative)
        guard !result.overflow, result.partialValue >= 0 else {
            return nil
        }
        return result.partialValue
    }

    static func validRange(offset: Int, length: Int, dataCount: Int) -> Range<Int>? {
        guard offset >= 0, length >= 0, dataCount >= 0 else {
            return nil
        }
        let end = offset.addingReportingOverflow(length)
        guard !end.overflow, end.partialValue <= dataCount else {
            return nil
        }
        return offset..<end.partialValue
    }
}

nonisolated struct TIFFIFDEntry: Sendable {
    let tag: UInt16
    let type: UInt16
    let count: Int
    let valueData: Data
    let endian: TIFFByteOrder
}

nonisolated enum TIFFIFDDecoder {
    private static let typeSizes: [UInt16: Int] = [
        1: 1, 2: 1, 3: 2, 4: 4, 5: 8,
        6: 1, 7: 1, 8: 2, 9: 4, 10: 8,
        11: 4, 12: 8
    ]

    static func entries(
        in data: Data,
        ifdOffset: Int,
        byteOrder: TIFFByteOrder,
        valueOffsetBases: [Int],
        maximumEntryCount: Int = 511,
        maximumValueCount: Int = 8_192
    ) -> [TIFFIFDEntry] {
        let reader = TIFFReader(data: data, byteOrder: byteOrder)
        guard let countValue = reader.uint16(at: ifdOffset) else {
            return []
        }

        let entryCount = Int(countValue)
        guard entryCount > 0, entryCount <= maximumEntryCount,
              let entriesByteCount = TIFFReader.byteCount(typeSize: 12, count: entryCount),
              let entriesOffset = TIFFReader.offset(base: ifdOffset, relative: 2),
              TIFFReader.validRange(offset: entriesOffset, length: entriesByteCount, dataCount: data.count) != nil else {
            return []
        }

        var entries: [TIFFIFDEntry] = []
        entries.reserveCapacity(entryCount)

        for index in 0..<entryCount {
            let relativeEntryOffset = index.multipliedReportingOverflow(by: 12)
            guard !relativeEntryOffset.overflow,
                  let entryOffset = TIFFReader.offset(base: entriesOffset, relative: relativeEntryOffset.partialValue),
                  let tag = reader.uint16(at: entryOffset),
                  let type = reader.uint16(at: entryOffset + 2),
                  let countValue = reader.uint32(at: entryOffset + 4),
                  let typeSize = typeSizes[type] else {
                continue
            }

            let valueCount = Int(countValue)
            guard valueCount > 0, valueCount <= maximumValueCount,
                  let byteCount = TIFFReader.byteCount(typeSize: typeSize, count: valueCount),
                  let valueData = valueData(
                    reader: reader,
                    entryOffset: entryOffset,
                    byteCount: byteCount,
                    valueOffsetBases: valueOffsetBases
                  ) else {
                continue
            }

            entries.append(TIFFIFDEntry(
                tag: tag,
                type: type,
                count: valueCount,
                valueData: valueData,
                endian: byteOrder
            ))
        }

        return entries
    }

    private static func valueData(
        reader: TIFFReader,
        entryOffset: Int,
        byteCount: Int,
        valueOffsetBases: [Int]
    ) -> Data? {
        guard byteCount > 0 else {
            return nil
        }
        if byteCount <= 4 {
            return TIFFReader.offset(base: entryOffset, relative: 8)
                .flatMap { reader.bytes(at: $0, count: byteCount) }
        }

        guard let offsetValue = reader.uint32(at: entryOffset + 8) else {
            return nil
        }
        for base in valueOffsetBases {
            if let valueOffset = TIFFReader.offset(base: base, relative: Int(offsetValue)),
               let bytes = reader.bytes(at: valueOffset, count: byteCount) {
                return bytes
            }
        }
        return nil
    }
}
