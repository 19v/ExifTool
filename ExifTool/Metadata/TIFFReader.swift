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
