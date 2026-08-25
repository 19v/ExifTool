//
//  AppleMetadataParsing.swift
//  ExifTool
//
//  Apple MakerNote support based on ExifTool's Apple tag table.
//

import Foundation
import ImageIO

nonisolated enum AppleMetadataExtractor {
    private static let tagNames: [UInt16: String] = [
        0x0001: "MakerNote 版本",
        0x0002: "AE 矩阵",
        0x0004: "AE 稳定",
        0x0005: "AE 目标",
        0x0006: "AE 平均值",
        0x0007: "AF 稳定",
        0x0008: "加速度向量",
        0x000a: "HDR 图像类型",
        0x000b: "连拍 UUID",
        0x000c: "对焦距离范围",
        0x000f: "OIS 模式",
        0x0011: "内容标识符",
        0x0014: "图像捕获类型",
        0x0015: "图像唯一 ID",
        0x0017: "实况照片视频索引",
        0x0019: "图像处理标志",
        0x001a: "质量提示",
        0x001d: "亮度噪声振幅",
        0x001f: "照片 App 特征标志",
        0x0020: "图像捕获请求 ID",
        0x0021: "HDR 余量",
        0x0023: "AF 性能",
        0x0025: "场景标志",
        0x0026: "信噪比类型",
        0x0027: "信噪比",
        0x002b: "照片标识符",
        0x002d: "色温",
        0x002e: "相机类型",
        0x002f: "对焦位置",
        0x0030: "HDR 增益",
        0x0038: "AF 测量深度",
        0x003d: "AF 置信度",
        0x003e: "颜色校正矩阵",
        0x003f: "绿色鬼影抑制状态",
        0x0040: "摄影风格",
        0x0041: "摄影风格渲染版本",
        0x0042: "摄影风格预设",
        0x004e: "Apple 0x004e",
        0x004f: "Apple 0x004f",
        0x0054: "Apple 0x0054",
        0x005a: "Apple 0x005a"
    ]

    static func section(from properties: [String: Any], imageData: Data? = nil) -> MetadataSection? {
        let systemValues = makerAppleDictionary(from: properties).map(parsedSystemValues) ?? [:]
        let rawValues = imageData.flatMap(jpegMakerNoteData).map(AppleMakerNoteParser.parse) ?? [:]
        let values = rawValues.merging(systemValues) { _, systemValue in systemValue }

        guard !values.isEmpty, isApple(properties, hasMakerNote: true) else {
            return nil
        }

        let items = values
            .sorted { lhs, rhs in
                let lhsOrder = order(for: lhs.key)
                let rhsOrder = order(for: rhs.key)
                return lhsOrder == rhsOrder
                    ? lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                    : lhsOrder < rhsOrder
            }
            .map { key, value in
                MetadataItem(id: "apple-\(key)", key: key, value: value)
            }

        return MetadataSection(id: "apple-parameters", title: "Apple 参数", items: items)
    }

    static func title(for tag: UInt16) -> String {
        tagNames[tag] ?? String(format: "Apple 0x%04x", tag)
    }

    static func formattedValue(for tag: UInt16, rawValue: Any) -> String? {
        switch tag {
        case 0x0003:
            return nil
        case 0x0004, 0x0007:
            guard let value = integer(from: rawValue) else { return readable(rawValue) }
            return value == 0 ? "否" : value == 1 ? "是" : String(value)
        case 0x000a:
            guard let value = integer(from: rawValue) else { return readable(rawValue) }
            return [3: "HDR 图像", 4: "原始图像"][value] ?? "未知（\(value)）"
        case 0x000c:
            guard let values = doubles(from: rawValue), values.count >= 2 else { return readable(rawValue) }
            let bounds = values.prefix(2).sorted()
            return String(format: "%.2f – %.2f m", bounds[0], bounds[1])
        case 0x0014:
            guard let value = integer(from: rawValue) else { return readable(rawValue) }
            return [1: "ProRAW", 2: "人像", 10: "照片", 11: "手动对焦", 12: "场景"][value] ?? "未知（\(value)）"
        case 0x0023:
            guard let values = integers(from: rawValue), values.count >= 2 else { return readable(rawValue) }
            let encoded = UInt32(bitPattern: Int32(truncatingIfNeeded: values[1]))
            return "\(values[0]), \(encoded >> 28), \(encoded & 0x0fff_ffff)"
        case 0x002e:
            guard let value = integer(from: rawValue) else { return readable(rawValue) }
            return [0: "后置超广角", 1: "后置主摄", 6: "前置"][value] ?? "未知（\(value)）"
        default:
            return readable(rawValue)
        }
    }

    private static func parsedSystemValues(_ dictionary: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]

        for (key, value) in dictionary {
            guard let tag = UInt16(key) else { continue }
            if tag == 0x0003 {
                appendRunTime(value, to: &result)
            } else if let formatted = formattedValue(for: tag, rawValue: value), !formatted.isEmpty {
                result[title(for: tag)] = formatted
            }
        }

        return result
    }

    static func appendRunTime(_ rawValue: Any, to result: inout [String: String]) {
        guard let dictionary = rawValue as? [String: Any] else { return }
        if let flags = integer(from: dictionary["flags"] as Any) {
            result["运行时间标志"] = runTimeFlags(flags)
        }
        if let value = integer64(from: dictionary["value"] as Any) {
            result["运行时间值"] = String(value)
        }
        if let epoch = integer64(from: dictionary["epoch"] as Any) {
            result["运行时间纪元"] = String(epoch)
        }
        if let scale = integer64(from: dictionary["timescale"] as Any) {
            result["运行时间刻度"] = String(scale)
        }
    }

    private static func runTimeFlags(_ flags: Int) -> String {
        let names = ["有效", "已舍入", "正无穷", "负无穷", "未定"]
        let enabled = names.enumerated().compactMap { index, name in
            flags & (1 << index) == 0 ? nil : name
        }
        return enabled.isEmpty ? String(flags) : enabled.joined(separator: ", ")
    }

    private static func makerAppleDictionary(from properties: [String: Any]) -> [String: Any]? {
        properties[String(kCGImagePropertyMakerAppleDictionary)] as? [String: Any]
    }

    private static func isApple(_ properties: [String: Any], hasMakerNote: Bool) -> Bool {
        if makerAppleDictionary(from: properties) != nil {
            return true
        }
        guard hasMakerNote else { return false }
        return flattenedStrings(properties).contains { key, value in
            (key.localizedCaseInsensitiveContains("make") || key.localizedCaseInsensitiveContains("model")) &&
            (value.localizedCaseInsensitiveContains("apple") ||
             value.localizedCaseInsensitiveContains("iphone") ||
             value.localizedCaseInsensitiveContains("ipad"))
        }
    }

    private static func flattenedStrings(_ value: Any, key: String = "") -> [(String, String)] {
        guard let dictionary = value as? [String: Any] else {
            return (value as? String).map { [(key, $0)] } ?? []
        }
        return dictionary.flatMap { nestedKey, nestedValue in
            flattenedStrings(nestedValue, key: key.isEmpty ? nestedKey : "\(key).\(nestedKey)")
        }
    }

    private static func order(for title: String) -> Int {
        let preferred = [
            "MakerNote 版本", "图像捕获类型", "相机类型", "内容标识符", "图像唯一 ID",
            "实况照片视频索引", "连拍 UUID", "AE 稳定", "AE 目标", "AE 平均值", "AF 稳定",
            "对焦距离范围", "对焦位置", "OIS 模式", "加速度向量", "色温", "HDR 图像类型",
            "HDR 余量", "HDR 增益", "运行时间标志", "运行时间值", "运行时间纪元", "运行时间刻度"
        ]
        return preferred.firstIndex(of: title) ?? Int.max
    }

    private static func integer(from value: Any) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let value as Int: return value
        case let values as [Any] where values.count == 1: return integer(from: values[0])
        default: return nil
        }
    }

    private static func integer64(from value: Any) -> Int64? {
        switch value {
        case let number as NSNumber: return number.int64Value
        case let value as Int64: return value
        case let value as Int: return Int64(value)
        default: return nil
        }
    }

    private static func integers(from value: Any) -> [Int]? {
        if let values = value as? [Any] {
            let result = values.compactMap(integer)
            return result.count == values.count ? result : nil
        }
        return integer(from: value).map { [$0] }
    }

    private static func doubles(from value: Any) -> [Double]? {
        if let values = value as? [Any] {
            let result = values.compactMap { element -> Double? in
                if let number = element as? NSNumber { return number.doubleValue }
                if let text = element as? String { return Double(text) }
                return nil
            }
            return result.count == values.count ? result : nil
        }
        return nil
    }

    private static func readable(_ value: Any) -> String? {
        if let data = value as? Data {
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) {
                return MetadataParser.readableValue(plist)
            }
            return data.isEmpty ? nil : "二进制数据（\(data.count) 字节）"
        }
        return MetadataParser.readableValue(value)
    }

    private static func jpegMakerNoteData(from data: Data) -> Data? {
        guard data.count > 4, data[0] == 0xff, data[1] == 0xd8 else { return nil }
        var offset = 2

        while offset + 4 <= data.count {
            guard data[offset] == 0xff else { return nil }
            while offset < data.count, data[offset] == 0xff { offset += 1 }
            guard offset < data.count else { return nil }
            let marker = data[offset]
            offset += 1
            if marker == 0xda || marker == 0xd9 { return nil }
            guard let length = TIFFReader(data: data, byteOrder: .big).uint16(at: offset) else { return nil }
            let segmentStart = offset + 2
            let segmentEnd = offset + Int(length)
            guard length >= 2, segmentEnd <= data.count else { return nil }
            if marker == 0xe1,
               let makerNote = exifMakerNoteData(from: data.subdata(in: segmentStart..<segmentEnd)) {
                return makerNote
            }
            offset = segmentEnd
        }
        return nil
    }

    private static func exifMakerNoteData(from segment: Data) -> Data? {
        let exifHeader = Data([0x45, 0x78, 0x69, 0x66, 0x00, 0x00])
        guard segment.starts(with: exifHeader) else { return nil }
        let tiffStart = exifHeader.count
        guard let byteOrder = byteOrder(in: segment, at: tiffStart),
              TIFFReader(data: segment, byteOrder: byteOrder).uint16(at: tiffStart + 2) == 42,
              let firstOffset = TIFFReader(data: segment, byteOrder: byteOrder).uint32(at: tiffStart + 4),
              let ifd0 = TIFFReader.offset(base: tiffStart, relative: Int(firstOffset)),
              let exifEntry = TIFFIFDDecoder.rawEntry(forTag: 0x8769, in: segment, ifdOffset: ifd0, byteOrder: byteOrder),
              let exifIFD = TIFFReader.offset(base: tiffStart, relative: exifEntry.valueOrOffset),
              let makerEntry = TIFFIFDDecoder.rawEntry(forTag: 0x927c, in: segment, ifdOffset: exifIFD, byteOrder: byteOrder),
              makerEntry.count > 0 else {
            return nil
        }

        let makerOffset: Int?
        if makerEntry.count <= 4 {
            makerOffset = makerEntry.valueFieldOffset
        } else {
            makerOffset = TIFFReader.offset(base: tiffStart, relative: makerEntry.valueOrOffset)
        }
        guard let makerOffset,
              let range = TIFFReader.validRange(offset: makerOffset, length: makerEntry.count, dataCount: segment.count) else {
            return nil
        }
        return segment.subdata(in: range)
    }

    private static func byteOrder(in data: Data, at offset: Int) -> TIFFByteOrder? {
        guard offset + 2 <= data.count else { return nil }
        switch (data[offset], data[offset + 1]) {
        case (0x49, 0x49): return .little
        case (0x4d, 0x4d): return .big
        default: return nil
        }
    }
}

nonisolated enum AppleMakerNoteParser {
    static func parse(_ data: Data) -> [String: String] {
        guard let layout = layout(in: data) else { return [:] }
        let entries = TIFFIFDDecoder.entries(
            in: data,
            ifdOffset: layout.ifdOffset,
            byteOrder: layout.byteOrder,
            valueOffsetBases: [0]
        )
        var result: [String: String] = [:]

        for entry in entries {
            if entry.tag == 0x0003 {
                if let plist = propertyList(from: entry.valueData) {
                    AppleMetadataExtractor.appendRunTime(plist, to: &result)
                }
                continue
            }
            guard let rawValue = decodedValue(entry),
                  let value = AppleMetadataExtractor.formattedValue(for: entry.tag, rawValue: rawValue),
                  !value.isEmpty else {
                continue
            }
            result[AppleMetadataExtractor.title(for: entry.tag)] = value
        }
        return result
    }

    private static func layout(in data: Data) -> (ifdOffset: Int, byteOrder: TIFFByteOrder)? {
        let signature = Data("Apple iOS".utf8)
        guard data.starts(with: signature), data.count >= 16 else { return nil }
        let endianOffset = 12
        let byteOrder: TIFFByteOrder
        switch (data[endianOffset], data[endianOffset + 1]) {
        case (0x49, 0x49): byteOrder = .little
        case (0x4d, 0x4d): byteOrder = .big
        default: return nil
        }
        return (endianOffset + 2, byteOrder)
    }

    private static func decodedValue(_ entry: TIFFIFDEntry) -> Any? {
        let reader = TIFFReader(data: entry.valueData, byteOrder: entry.endian)
        switch entry.type {
        case 1, 7:
            if entry.type == 7 { return entry.valueData }
            return entry.valueData.map(Int.init)
        case 2:
            return String(data: entry.valueData.prefix { $0 != 0 }, encoding: .utf8)
        case 3:
            return (0..<entry.count).compactMap { reader.uint16(at: $0 * 2).map(Int.init) }
        case 4:
            return (0..<entry.count).compactMap { reader.uint32(at: $0 * 4).map(Int.init) }
        case 6:
            return entry.valueData.map { Int(Int8(bitPattern: $0)) }
        case 8:
            return (0..<entry.count).compactMap { reader.int16(at: $0 * 2).map(Int.init) }
        case 9:
            return (0..<entry.count).compactMap { reader.int32(at: $0 * 4).map(Int.init) }
        case 5, 10:
            let values: [Double] = (0..<entry.count).compactMap { index in
                let offset = index * 8
                let numerator: Double
                let denominator: Double
                if entry.type == 10 {
                    guard let top = reader.int32(at: offset), let bottom = reader.int32(at: offset + 4) else { return nil }
                    numerator = Double(top)
                    denominator = Double(bottom)
                } else {
                    guard let top = reader.uint32(at: offset), let bottom = reader.uint32(at: offset + 4) else { return nil }
                    numerator = Double(top)
                    denominator = Double(bottom)
                }
                return denominator == 0 ? nil : numerator / denominator
            }
            return values
        default:
            return nil
        }
    }

    private static func propertyList(from data: Data) -> Any? {
        try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }
}
