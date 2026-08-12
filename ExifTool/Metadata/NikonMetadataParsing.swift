//
//  NikonMetadataParsing.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Foundation
import ImageIO

nonisolated enum NikonMetadataExtractor {
    private struct Field {
        let title: String
        let aliases: [String]
    }

    private struct Candidate {
        let key: String
        let value: Any
    }

    private static let fields: [Field] = [
        Field(title: "优化校准", aliases: ["PictureControl", "PictureControlData", "ImageOptimization", "ImageAdjustment"]),
        Field(title: "白平衡", aliases: ["WhiteBalance"]),
        Field(title: "白平衡微调", aliases: ["WhiteBalanceFineTune", "WhiteBalanceShift", "WB_RBLevels", "WBRBLevels", "WhiteBalanceRBLevels"]),
        Field(title: "色彩空间", aliases: ["ColorSpace"]),
        Field(title: "动态 D-Lighting", aliases: ["ActiveD-Lighting", "ActiveDLighting"]),
        Field(title: "高 ISO 降噪", aliases: ["HighISONoiseReduction", "NoiseReduction"]),
        Field(title: "镜头信息", aliases: ["Lens", "LensID"]),
        Field(title: "镜头类型", aliases: ["LensType"]),
        Field(title: "防抖", aliases: ["VibrationReduction", "VRInfo", "ImageStabilization"]),
        Field(title: "闪光灯", aliases: ["FlashMode", "FlashType", "FlashSetting", "FlashExposureComp"]),
        Field(title: "拍摄模式", aliases: ["ShootingMode", "SceneMode", "VariProgram", "CropHiSpeed", "ShutterMode"]),
        Field(title: "快门次数", aliases: ["ShutterCount", "MechanicalShutterCount"]),
        Field(title: "ISO", aliases: ["ISO", "ISOSetting", "ISOSelection"]),
        Field(title: "对焦模式", aliases: ["FocusMode"]),
        Field(title: "锐度", aliases: ["Sharpness"]),
        Field(title: "色彩", aliases: ["Saturation", "ColorMode"]),
        Field(title: "色调补偿", aliases: ["ToneComp"]),
        Field(title: "色温", aliases: ["ColorTemperatureAuto"])
    ]

    static func section(from properties: [String: Any]) -> MetadataSection? {
        guard isNikon(properties) else {
            return nil
        }

        let parsedMakerNote = makerNoteData(from: properties).flatMap(NikonMakerNoteParser.parse) ?? [:]
        let candidates = flatten(properties)
        var usedTitles = Set<String>()
        var usedKeys = Set<String>()
        var items: [MetadataItem] = []

        for field in fields {
            if let parsedValue = parsedMakerNote[field.title], !parsedValue.isEmpty {
                items.append(MetadataItem(id: "nikon-\(field.title)", key: field.title, value: parsedValue))
                usedTitles.insert(field.title)
                continue
            }

            guard let candidate = firstCandidate(for: field, in: candidates, usedKeys: usedKeys) else {
                continue
            }

            let readableValue = NikonMakerNoteParser.decodeFallbackValue(for: normalized(candidate.key), rawValue: candidate.value)
            guard !readableValue.isEmpty else {
                continue
            }

            usedKeys.insert(normalized(candidate.key))
            usedTitles.insert(field.title)
            items.append(MetadataItem(id: "nikon-\(field.title)", key: field.title, value: readableValue))
        }

        let extraItems = parsedMakerNote
            .filter { !usedTitles.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { key, value in
                MetadataItem(id: "nikon-extra-\(key)", key: key, value: value)
            }

        items.append(contentsOf: extraItems)

        guard !items.isEmpty else {
            return nil
        }

        return MetadataSection(id: "nikon-parameters", title: "Nikon 参数", items: items)
    }

    private static func isNikon(_ properties: [String: Any]) -> Bool {
        flatten(properties).contains { candidate in
            let key = normalized(candidate.key)
            guard (key.contains("make") || key.contains("model")),
                  let text = candidate.value as? String else {
                return false
            }

            return text.localizedCaseInsensitiveContains("nikon")
        }
    }

    private static func makerNoteData(from properties: [String: Any]) -> Data? {
        guard let exif = properties[String(kCGImagePropertyExifDictionary)] as? [String: Any] else {
            return nil
        }

        let makerNoteKeys = [
            String(kCGImagePropertyExifMakerNote),
            "MakerNote",
            "{Exif}MakerNote"
        ]

        for key in makerNoteKeys {
            guard let value = exif[key] else {
                continue
            }

            if let data = value as? Data {
                return data
            }

            if let data = value as? NSData {
                return data as Data
            }

            if let bytes = value as? [UInt8] {
                return Data(bytes)
            }
        }

        return nil
    }

    private static func firstCandidate(for field: Field, in candidates: [Candidate], usedKeys: Set<String>) -> Candidate? {
        for alias in field.aliases {
            let normalizedAlias = normalized(alias)
            if let exact = candidates.first(where: { normalized($0.key) == normalizedAlias && !usedKeys.contains(normalized($0.key)) }) {
                return exact
            }

            if let contained = candidates.first(where: { normalized($0.key).contains(normalizedAlias) && !usedKeys.contains(normalized($0.key)) }) {
                return contained
            }
        }

        return nil
    }

    private static func flatten(_ value: Any, parentKey: String = "") -> [Candidate] {
        guard let dictionary = value as? [String: Any] else {
            return parentKey.isEmpty ? [] : [Candidate(key: parentKey, value: value)]
        }

        return dictionary.flatMap { key, nestedValue -> [Candidate] in
            let readableKey = key
                .replacingOccurrences(of: "{Exif}", with: "")
                .replacingOccurrences(of: "{TIFF}", with: "")
                .replacingOccurrences(of: "{GPS}", with: "")
            let combinedKey = parentKey.isEmpty ? readableKey : "\(parentKey).\(readableKey)"
            return flatten(nestedValue, parentKey: combinedKey)
        }
    }

    private static func normalized(_ key: String) -> String {
        key
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: ".", with: "")
    }
}

nonisolated enum NikonMakerNoteParser {
    private typealias Endian = TIFFByteOrder

    private typealias IFDEntry = TIFFIFDEntry

    static func parse(_ data: Data) -> [String: String] {
        guard let tiff = locateTIFFHeader(in: data),
              let ifdOffsetValue = readUInt32(data, at: tiff.start + 4, endian: tiff.endian) else {
            return [:]
        }

        let ifdOffset = tiff.start + Int(ifdOffsetValue)
        let entries = parseIFD(in: data, offset: ifdOffset, tiffStart: tiff.start, endian: tiff.endian)
        guard !entries.isEmpty else {
            return [:]
        }

        var fields: [String: String] = [:]

        for entry in entries {
            for (title, component) in components(for: entry) {
                append(component, to: title, in: &fields)
            }
        }

        return fields
    }

    static func decodeFallbackValue(for normalizedKey: String, rawValue: Any) -> String {
        switch true {
        case matches(normalizedKey, aliases: ["whitebalancefinetune", "whitebalanceshift", "wbrblevels", "whitebalancerblevels"]):
            return fallbackWhiteBalanceFineTuneValue(rawValue) ?? MetadataParser.readableValue(rawValue)
        case matches(normalizedKey, aliases: ["colorspace"]):
            guard let value = firstInteger(from: rawValue) else { return MetadataParser.readableValue(rawValue) }
            return colorSpace[value] ?? String(value)
        case matches(normalizedKey, aliases: ["activedlighting"]):
            guard let value = firstInteger(from: rawValue) else { return MetadataParser.readableValue(rawValue) }
            return activeDLighting[value] ?? String(value)
        case matches(normalizedKey, aliases: ["highisonoisereduction"]):
            guard let value = firstInteger(from: rawValue) else { return MetadataParser.readableValue(rawValue) }
            return highISONoiseReduction[value] ?? String(value)
        case matches(normalizedKey, aliases: ["shuttermode"]):
            guard let value = firstInteger(from: rawValue) else { return MetadataParser.readableValue(rawValue) }
            return shutterMode[value] ?? String(value)
        default:
            return MetadataParser.readableValue(rawValue)
        }
    }

    private static func components(for entry: IFDEntry) -> [(String, String)] {
        switch entry.tag {
        case 0x0002:
            guard let iso = isoDescription(entry) else { return [] }
            return [("ISO", iso)]
        case 0x0003:
            return stringComponent("色彩", from: entry)
        case 0x0004:
            return stringComponent("图像质量", from: entry)
        case 0x0005:
            return stringComponent("白平衡", from: entry)
        case 0x0006:
            return stringComponent("锐度", from: entry)
        case 0x0007:
            return stringComponent("对焦模式", from: entry)
        case 0x0008:
            return stringComponent("闪光灯", from: entry).map { ("闪光灯", "同步模式: \($0.1)") }
        case 0x0009:
            return stringComponent("闪光灯", from: entry).map { ("闪光灯", "类型: \($0.1)") }
        case 0x000b:
            guard let tune = whiteBalanceFineTuneDescription(entry) else { return [] }
            return [("白平衡微调", tune)]
        case 0x0012:
            guard let compensation = nikonFractionDescription(entry) else { return [] }
            return [("闪光灯", "曝光补偿: \(compensation) EV")]
        case 0x001b:
            guard let crop = cropHiSpeedDescription(entry) else { return [] }
            return [("拍摄模式", crop)]
        case 0x001e:
            guard let value = numericValues(entry).first else { return [] }
            return [("色彩空间", colorSpace[value] ?? String(value))]
        case 0x001f:
            return vrInfoComponents(from: entry.valueData)
        case 0x0022:
            guard let value = numericValues(entry).first else { return [] }
            return [("动态 D-Lighting", activeDLighting[value] ?? String(value))]
        case 0x0023:
            return pictureControlComponents(from: entry.valueData)
        case 0x0034:
            guard let value = numericValues(entry).first else { return [] }
            return [("拍摄模式", "快门模式: \(shutterMode[value] ?? String(value))")]
        case 0x0037:
            guard let value = numericValues(entry).first else { return [] }
            return [("快门次数", "机械快门: \(value)")]
        case 0x003f:
            let fineTune = Array(rationalArray(entry).prefix(2).enumerated().map { index, value in
                let channel = index == 0 ? "R" : "B"
                return "\(channel) \(formatSignedRational(value))"
            })
            guard !fineTune.isEmpty else { return [] }
            return [("白平衡微调", fineTune.joined(separator: ", "))]
        case 0x004f:
            guard let value = numericValues(entry).first else { return [] }
            return [("色温", "\(value) K")]
        case 0x0080:
            return stringComponent("优化校准", from: entry)
        case 0x0081:
            return stringComponent("色调补偿", from: entry)
        case 0x0083:
            guard let value = numericValues(entry).first else { return [] }
            return [("镜头类型", lensTypeDescription(value))]
        case 0x0084:
            guard let lens = lensDescription(entry) else { return [] }
            return [("镜头信息", lens)]
        case 0x0087:
            guard let value = numericValues(entry).first else { return [] }
            return [("闪光灯", flashMode[value] ?? String(value))]
        case 0x0089:
            guard let value = numericValues(entry).first else { return [] }
            return [("拍摄模式", shootingModeDescription(value))]
        case 0x008d:
            return stringComponent("色彩", from: entry).map { ("色彩", "色相: \($0.1)") }
        case 0x008f:
            return stringComponent("拍摄模式", from: entry)
        case 0x0095:
            return stringComponent("高 ISO 降噪", from: entry)
        case 0x00a7:
            guard let value = numericValues(entry).first else { return [] }
            return [("快门次数", String(value))]
        case 0x00a9:
            return stringComponent("优化校准", from: entry)
        case 0x00aa:
            return stringComponent("色彩", from: entry)
        case 0x00ab:
            return stringComponent("拍摄模式", from: entry)
        case 0x00ac:
            return stringComponent("防抖", from: entry)
        case 0x00b1:
            guard let value = numericValues(entry).first else { return [] }
            return [("高 ISO 降噪", highISONoiseReduction[value] ?? String(value))]
        default:
            return []
        }
    }

    private static func append(_ component: String, to title: String, in fields: inout [String: String]) {
        guard !component.isEmpty else {
            return
        }

        if let existing = fields[title], !existing.contains(component) {
            fields[title] = "\(existing)\n\(component)"
        } else if fields[title] == nil {
            fields[title] = component
        }
    }

    private static func stringComponent(_ title: String, from entry: IFDEntry) -> [(String, String)] {
        guard let value = asciiString(entry.valueData) else {
            return []
        }

        return [(title, formatNikonText(value))]
    }

    private static func locateTIFFHeader(in data: Data) -> (start: Int, endian: Endian)? {
        guard data.count >= 4 else {
            return nil
        }

        let limit = max(0, min(data.count - 4, 32))

        for offset in 0...limit {
            if data[offset] == 0x49, data[offset + 1] == 0x49, data[offset + 2] == 0x2a, data[offset + 3] == 0x00 {
                return (offset, .little)
            }

            if data[offset] == 0x4d, data[offset + 1] == 0x4d, data[offset + 2] == 0x00, data[offset + 3] == 0x2a {
                return (offset, .big)
            }
        }

        return nil
    }

    private static func parseIFD(in data: Data, offset: Int, tiffStart: Int, endian: Endian) -> [IFDEntry] {
        TIFFIFDDecoder.entries(
            in: data,
            ifdOffset: offset,
            byteOrder: endian,
            valueOffsetBases: [tiffStart],
            maximumValueCount: 4_096
        )
    }

    private static func numericValues(_ entry: IFDEntry) -> [Int] {
        switch entry.type {
        case 1, 7:
            return entry.valueData.prefix(entry.count).map(Int.init)
        case 3:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 2), by: 2).compactMap {
                readUInt16(entry.valueData, at: $0, endian: entry.endian).map(Int.init)
            }
        case 4:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 4), by: 4).compactMap {
                readUInt32(entry.valueData, at: $0, endian: entry.endian).map(Int.init)
            }
        case 9:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 4), by: 4).compactMap {
                readInt32(entry.valueData, at: $0, endian: entry.endian).map(Int.init)
            }
        default:
            return []
        }
    }

    private static func signedShortValues(_ entry: IFDEntry) -> [Int] {
        guard entry.type == 8 || entry.type == 3 else {
            return []
        }

        return stride(from: 0, to: min(entry.valueData.count, entry.count * 2), by: 2).compactMap {
            readInt16(entry.valueData, at: $0, endian: entry.endian).map(Int.init)
        }
    }

    private static func rationalArray(_ entry: IFDEntry) -> [Double] {
        switch entry.type {
        case 5:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 8), by: 8).compactMap { offset in
                guard
                    let numerator = readUInt32(entry.valueData, at: offset, endian: entry.endian),
                    let denominator = readUInt32(entry.valueData, at: offset + 4, endian: entry.endian),
                    denominator != 0
                else {
                    return nil
                }

                return Double(numerator) / Double(denominator)
            }
        case 10:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 8), by: 8).compactMap { offset in
                guard
                    let numerator = readInt32(entry.valueData, at: offset, endian: entry.endian),
                    let denominator = readInt32(entry.valueData, at: offset + 4, endian: entry.endian),
                    denominator != 0
                else {
                    return nil
                }

                return Double(numerator) / Double(denominator)
            }
        default:
            return []
        }
    }

    private static func isoDescription(_ entry: IFDEntry) -> String? {
        let values = numericValues(entry)
        guard values.count >= 2 else {
            return nil
        }

        if values[0] == 1 {
            return "Hi \(values[1])"
        }

        return String(values[1])
    }

    private static func whiteBalanceFineTuneDescription(_ entry: IFDEntry) -> String? {
        let values = signedShortValues(entry)
        guard !values.isEmpty else {
            return nil
        }

        if values.count >= 2 {
            return "R \(formatSigned(values[0])), B \(formatSigned(values[1]))"
        }

        return "R \(formatSigned(values[0]))"
    }

    private static func nikonFractionDescription(_ entry: IFDEntry) -> String? {
        let bytes = [UInt8](entry.valueData.prefix(3))
        guard bytes.count == 3, bytes[2] != 0 else {
            return nil
        }

        let numerator = Int(Int8(bitPattern: bytes[0]))
        let denominator = Int(bytes[2])
        let value = Double(numerator) * Double(bytes[1]) / Double(denominator)
        return formatSignedRational(value)
    }

    private static func cropHiSpeedDescription(_ entry: IFDEntry) -> String? {
        let values = numericValues(entry)
        guard let mode = values.first else {
            return nil
        }

        if let label = cropHiSpeed[mode] {
            return "\(AppLocalization.string("metadata.value.cropMode")): \(label)"
        }

        return "\(AppLocalization.string("metadata.value.cropMode")): \(values.map(String.init).joined(separator: ", "))"
    }

    private static func fallbackWhiteBalanceFineTuneValue(_ rawValue: Any) -> String? {
        guard let values = integerArray(from: rawValue), !values.isEmpty else {
            return nil
        }

        if values.count >= 2 {
            return "R \(formatSigned(values[0])), B \(formatSigned(values[1]))"
        }

        return "R \(formatSigned(values[0]))"
    }

    private static func vrInfoComponents(from data: Data) -> [(String, String)] {
        var parts: [String] = []

        if data.count > 4 {
            let value = Int(data[4])
            if let description = vibrationReduction[value] {
                parts.append(description)
            }
        }

        if data.count > 6 {
            let value = Int(data[6])
            if let description = vrMode[value] {
                parts.append("模式: \(description)")
            }
        }

        if data.count > 8 {
            let value = Int(data[8])
            if let description = vrType[value] {
                parts.append(description)
            }
        }

        guard !parts.isEmpty else {
            return []
        }

        return [("防抖", parts.joined(separator: ", "))]
    }

    private static func pictureControlComponents(from data: Data) -> [(String, String)] {
        guard data.count >= 28,
              let version = asciiString(data.prefix(2)) else {
            return []
        }

        switch version {
        case "01":
            return pictureControlV1(from: data)
        case "02":
            return pictureControlV2(from: data)
        case "03":
            return pictureControlV3(from: data)
        default:
            return []
        }
    }

    private static func pictureControlV1(from data: Data) -> [(String, String)] {
        var components: [(String, String)] = []

        if let name = readFixedString(data, offset: 4, length: 20) {
            components.append(("优化校准", "配置: \(formatNikonText(name))"))
        }
        if let base = readFixedString(data, offset: 24, length: 20) {
            components.append(("优化校准", "基础: \(formatNikonText(base))"))
        }
        components.append(contentsOf: pictureControlAdjustComponents(data: data, quickOffset: 49, sharpnessOffset: 50, clarityOffset: nil, contrastOffset: 51, brightnessOffset: 52, saturationOffset: 53, hueOffset: 54, filterOffset: 55, toningOffset: 56, toningSaturationOffset: 57))
        return components
    }

    private static func pictureControlV2(from data: Data) -> [(String, String)] {
        var components: [(String, String)] = []

        if let name = readFixedString(data, offset: 4, length: 20) {
            components.append(("优化校准", "配置: \(formatNikonText(name))"))
        }
        if let base = readFixedString(data, offset: 24, length: 20) {
            components.append(("优化校准", "基础: \(formatNikonText(base))"))
        }
        components.append(contentsOf: pictureControlAdjustComponents(data: data, quickOffset: 49, sharpnessOffset: 51, clarityOffset: 53, contrastOffset: 55, brightnessOffset: 57, saturationOffset: 59, hueOffset: 61, filterOffset: 63, toningOffset: 64, toningSaturationOffset: 65))
        return components
    }

    private static func pictureControlV3(from data: Data) -> [(String, String)] {
        var components: [(String, String)] = []

        if let name = readFixedString(data, offset: 8, length: 20) {
            components.append(("优化校准", "配置: \(formatNikonText(name))"))
        }
        if let base = readFixedString(data, offset: 28, length: 20) {
            components.append(("优化校准", "基础: \(formatNikonText(base))"))
        }
        components.append(contentsOf: pictureControlAdjustComponents(data: data, quickOffset: 55, sharpnessOffset: 57, clarityOffset: 61, contrastOffset: 63, brightnessOffset: 65, saturationOffset: 67, hueOffset: 69, filterOffset: 71, toningOffset: 72, toningSaturationOffset: 73))
        if let midRange = pictureControlValue(data, offset: 59, scale: 4) {
            components.append(("优化校准", "中间锐度: \(midRange)"))
        }
        return components
    }

    private static func pictureControlAdjustComponents(
        data: Data,
        quickOffset: Int,
        sharpnessOffset: Int,
        clarityOffset: Int?,
        contrastOffset: Int,
        brightnessOffset: Int,
        saturationOffset: Int,
        hueOffset: Int,
        filterOffset: Int,
        toningOffset: Int,
        toningSaturationOffset: Int
    ) -> [(String, String)] {
        var components: [(String, String)] = []

        if let quick = pictureControlValue(data, offset: quickOffset, scale: 1) {
            components.append(("优化校准", "快速调整: \(quick)"))
        }
        if let sharpness = pictureControlValue(data, offset: sharpnessOffset, scale: 4) {
            components.append(("优化校准", "锐度: \(sharpness)"))
        }
        if let clarityOffset, let clarity = pictureControlValue(data, offset: clarityOffset, scale: 4) {
            components.append(("优化校准", "清晰度: \(clarity)"))
        }
        if let contrast = pictureControlValue(data, offset: contrastOffset, scale: 4) {
            components.append(("优化校准", "对比度: \(contrast)"))
        }
        if let brightness = pictureControlValue(data, offset: brightnessOffset, scale: 4) {
            components.append(("优化校准", "亮度: \(brightness)"))
        }
        if let saturation = pictureControlValue(data, offset: saturationOffset, scale: 4) {
            components.append(("优化校准", "饱和度: \(saturation)"))
        }
        if let hue = pictureControlValue(data, offset: hueOffset, scale: 4) {
            components.append(("优化校准", "色相: \(hue)"))
        }
        if let value = byte(at: filterOffset, in: data), value != 0xff, let effect = filterEffect[Int(value)] {
            components.append(("优化校准", "滤镜效果: \(effect)"))
        }
        if let value = byte(at: toningOffset, in: data), value != 0xff, let effect = toningEffect[Int(value)] {
            components.append(("优化校准", "色调效果: \(effect)"))
        }
        if let toning = pictureControlValue(data, offset: toningSaturationOffset, scale: 4) {
            components.append(("优化校准", "色调饱和度: \(toning)"))
        }

        return components
    }

    private static func pictureControlValue(_ data: Data, offset: Int, scale: Double) -> String? {
        guard let rawValue = byte(at: offset, in: data), rawValue != 0xff else {
            return nil
        }

        let adjusted = Double(Int(rawValue) - 0x80) / scale
        if adjusted == 0 {
            return "0"
        }
        if adjusted.rounded() == adjusted {
            return formatSigned(Int(adjusted))
        }

        return adjusted > 0 ? String(format: "+%.2f", adjusted) : String(format: "%.2f", adjusted)
    }

    private static func lensDescription(_ entry: IFDEntry) -> String? {
        let values = rationalArray(entry)
        guard values.count >= 4 else {
            return nil
        }

        let focalPart: String
        if abs(values[0] - values[1]) < 0.01 {
            focalPart = "\(formatCompact(values[0]))mm"
        } else {
            focalPart = "\(formatCompact(values[0]))-\(formatCompact(values[1]))mm"
        }

        let aperturePart: String
        if abs(values[2] - values[3]) < 0.01 {
            aperturePart = "f/\(formatCompact(values[2]))"
        } else {
            aperturePart = "f/\(formatCompact(values[2]))-\(formatCompact(values[3]))"
        }

        return "\(focalPart) \(aperturePart)"
    }

    private static func lensTypeDescription(_ value: Int) -> String {
        guard value != 0 else {
            return "AF"
        }

        var parts: [String] = []
        if value & 0x01 != 0 { parts.append("MF") }
        if value & 0x02 != 0, value & 0x04 == 0 { parts.append("D") }
        if value & 0x04 != 0 { parts.append("G") }
        if value & 0x08 != 0 { parts.append("VR") }
        if value & 0x10 != 0 { parts.append("1") }
        if value & 0x20 != 0 { parts.append("FT-1") }
        if value & 0x40 != 0 { parts.insert("E", at: 0) }
        if value & 0x80 != 0 { parts.append("AF-P") }

        return parts.isEmpty ? String(value) : parts.joined(separator: " ")
    }

    private static func shootingModeDescription(_ value: Int) -> String {
        var modes: [String] = []

        if value & 0x87 == 0 {
            modes.append("Single-Frame")
        } else if value & 0x01 != 0 {
            modes.append("Continuous")
        }

        if value & 0x02 != 0 { modes.append("Delay") }
        if value & 0x04 != 0 { modes.append("PC Control") }
        if value & 0x08 != 0 { modes.append("Self-timer") }
        if value & 0x10 != 0 { modes.append("Exposure Bracketing") }
        if value & 0x20 != 0 { modes.append("Auto ISO") }
        if value & 0x40 != 0 { modes.append("White-Balance Bracketing") }
        if value & 0x80 != 0 { modes.append("IR Control") }
        if value & 0x100 != 0 { modes.append("D-Lighting Bracketing") }
        if value & 0x800 != 0 { modes.append("Pre-capture") }

        return modes.isEmpty ? String(value) : modes.joined(separator: ", ")
    }

    private static func formatNikonText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        return trimmed
            .lowercased()
            .split(separator: " ")
            .map { token in
                token
                    .split(separator: "/")
                    .map { segment in
                        segment.prefix(1).uppercased() + segment.dropFirst()
                    }
                    .joined(separator: "/")
            }
            .joined(separator: " ")
    }

    private static func asciiString<T: DataProtocol>(_ data: T) -> String? {
        let bytes = Data(data).prefix { $0 != 0 }
        guard !bytes.isEmpty else {
            return nil
        }

        return String(data: Data(bytes), encoding: .ascii)
    }

    private static func readFixedString(_ data: Data, offset: Int, length: Int) -> String? {
        guard offset >= 0, offset + length <= data.count else {
            return nil
        }

        return asciiString(data[offset..<(offset + length)])
    }

    private static func byte(at offset: Int, in data: Data) -> UInt8? {
        guard offset >= 0, offset < data.count else {
            return nil
        }

        return data[offset]
    }

    private static func firstInteger(from rawValue: Any) -> Int? {
        switch rawValue {
        case let number as NSNumber:
            return number.intValue
        case let array as [NSNumber]:
            return array.first?.intValue
        case let array as [Int]:
            return array.first
        case let array as [Any]:
            return array.compactMap { firstInteger(from: $0) }.first
        default:
            return nil
        }
    }

    private static func integerArray(from rawValue: Any) -> [Int]? {
        switch rawValue {
        case let number as NSNumber:
            return [number.intValue]
        case let array as [NSNumber]:
            return array.map(\.intValue)
        case let array as [Int]:
            return array
        case let array as [Any]:
            let values = array.compactMap { firstInteger(from: $0) }
            return values.isEmpty ? nil : values
        default:
            return nil
        }
    }

    private static func matches(_ normalizedKey: String, aliases: [String]) -> Bool {
        aliases.contains { alias in
            normalizedKey == alias || normalizedKey.contains(alias) || normalizedKey.hasSuffix(alias)
        }
    }

    private static func formatSigned(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }

    private static func formatSignedRational(_ value: Double) -> String {
        if value.rounded() == value {
            return formatSigned(Int(value))
        }

        return value > 0 ? String(format: "+%.2f", value) : String(format: "%.2f", value)
    }

    private static func formatCompact(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.1f", value)
    }

    private static func readUInt16(_ data: Data, at offset: Int, endian: Endian) -> UInt16? {
        TIFFReader(data: data, byteOrder: endian).uint16(at: offset)
    }

    private static func readInt16(_ data: Data, at offset: Int, endian: Endian) -> Int16? {
        readUInt16(data, at: offset, endian: endian).map { Int16(bitPattern: $0) }
    }

    private static func readUInt32(_ data: Data, at offset: Int, endian: Endian) -> UInt32? {
        TIFFReader(data: data, byteOrder: endian).uint32(at: offset)
    }

    private static func readInt32(_ data: Data, at offset: Int, endian: Endian) -> Int32? {
        readUInt32(data, at: offset, endian: endian).map { Int32(bitPattern: $0) }
    }

    private static let colorSpace: [Int: String] = [
        1: "sRGB",
        2: "Adobe RGB",
        4: "BT.2100"
    ]

    private static let activeDLighting: [Int: String] = [
        0: "Off",
        1: "Low",
        3: "Normal",
        5: "High",
        7: "Extra High",
        8: "Extra High 1",
        9: "Extra High 2",
        10: "Extra High 3",
        11: "Extra High 4",
        0xffff: "Auto"
    ]

    private static let highISONoiseReduction: [Int: String] = [
        0: "Off",
        1: "Minimal",
        2: "Low",
        3: "Medium Low",
        4: "Normal",
        5: "Medium High",
        6: "High"
    ]

    private static let flashMode: [Int: String] = [
        0: "Did Not Fire",
        1: "Fired, Manual",
        3: "Not Ready",
        7: "Fired, External",
        8: "Fired, Commander Mode",
        9: "Fired, TTL Mode",
        18: "LED Light"
    ]

    private static let shutterMode: [Int: String] = [
        0: "Mechanical",
        16: "Electronic",
        48: "Electronic Front Curtain",
        64: "Electronic (Movie)",
        80: "Auto (Mechanical)",
        81: "Auto (Electronic Front Curtain)",
        96: "Electronic (High Speed)"
    ]

    private static let cropHiSpeed: [Int: String] = [
        0: "Off",
        1: "1.3x Crop",
        2: "DX Crop",
        3: "5:4 Crop",
        4: "3:2 Crop",
        5: "16:9 Crop"
    ]

    private static let vibrationReduction: [Int: String] = [
        0: "n/a",
        1: "On",
        2: "Off"
    ]

    private static let vrMode: [Int: String] = [
        0: "Off/Normal",
        1: "Normal",
        2: "Active",
        3: "Sport"
    ]

    private static let vrType: [Int: String] = [
        2: "In-body",
        3: "In-body + Lens"
    ]

    private static let filterEffect: [Int: String] = [
        0x80: "Off",
        0x81: "Yellow",
        0x82: "Orange",
        0x83: "Red",
        0x84: "Green"
    ]

    private static let toningEffect: [Int: String] = [
        0x80: "B&W",
        0x81: "Sepia",
        0x82: "Cyanotype",
        0x83: "Red",
        0x84: "Yellow",
        0x85: "Green",
        0x86: "Blue-green",
        0x87: "Blue",
        0x88: "Purple-blue",
        0x89: "Red-purple"
    ]
}
