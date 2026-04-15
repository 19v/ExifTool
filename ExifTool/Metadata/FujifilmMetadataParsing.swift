//
//  FujifilmMetadataParsing.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Foundation
import ImageIO

enum CameraMetadataSectionBuilder {
    static func sections(from properties: [String: Any]) -> [MetadataSection] {
        [
            FujifilmMetadataExtractor.section(from: properties),
            NikonMetadataExtractor.section(from: properties)
        ].compactMap { $0 }
    }
}

enum FujifilmMetadataExtractor {
    private struct Field {
        let title: String
        let aliases: [String]
    }

    private struct Candidate {
        let key: String
        let value: Any
    }

    private static let fields: [Field] = [
        Field(title: "胶片风格", aliases: ["FilmMode", "FilmSimulation", "FilmSimulationMode"]),
        Field(title: "动态范围", aliases: ["DynamicRange", "DynamicRangeSetting", "DRangePriority", "DRPriority"]),
        Field(title: "白平衡", aliases: ["WhiteBalance", "WhiteBalanceMode"]),
        Field(title: "白平衡偏移", aliases: ["WhiteBalanceFineTune", "WhiteBalanceShift", "WBShift", "WB_RBLevels", "WBRBLevels", "WBGRBLevels", "WhiteBalanceRBLevels"]),
        Field(title: "色温", aliases: ["ColorTemperature"]),
        Field(title: "高光", aliases: ["HighlightTone", "Highlight", "Highlights"]),
        Field(title: "阴影", aliases: ["ShadowTone", "Shadow", "Shadows"]),
        Field(title: "色彩", aliases: ["Color", "Saturation", "ColorChromeEffect", "ColorChromeFXBlue"]),
        Field(title: "高级滤镜", aliases: ["AdvancedFilter"]),
        Field(title: "锐度", aliases: ["Sharpness"]),
        Field(title: "降噪", aliases: ["NoiseReduction", "HighISONoiseReduction"]),
        Field(title: "颗粒效果", aliases: ["GrainEffect", "GrainEffectRoughness", "GrainEffectSize"]),
        Field(title: "清晰度", aliases: ["Clarity"]),
        Field(title: "镜头像差校正", aliases: ["LensModulationOptimizer", "PeripheralLighting", "ChromaticAberrationCorrection", "DistortionCorrection"]),
        Field(title: "拍摄模式", aliases: ["ShootingMode", "ExposureMode", "DriveMode", "ShutterType", "MultipleExposure", "CompositeImageMode", "SceneRecognition"]),
        Field(title: "对焦模式", aliases: ["FocusMode", "AFMode", "FocusPixel", "Macro"]),
        Field(title: "闪光灯", aliases: ["FujiFlashMode", "FlashExposureComp", "SlowSync"]),
        Field(title: "防抖", aliases: ["ImageStabilization"]),
        Field(title: "EXR 模式", aliases: ["EXRMode", "EXRAuto"]),
        Field(title: "包围曝光", aliases: ["AutoBracketing", "WhiteBalanceBracketing"]),
        Field(title: "胶片颗粒/色彩效果", aliases: ["ColorChromeEffect", "ColorChromeFXBlue", "MonochromaticColor"]),
        Field(title: "机内处理", aliases: ["DevelopmentDynamicRange", "ImageGeneration", "RawDevelopmentProcess", "DRangePriority", "DRangePriorityAuto", "DRangePriorityFixed"]),
        Field(title: "快门次数", aliases: ["ShutterCount", "ImageCount", "MechanicalShutterCount"]),
        Field(title: "评分", aliases: ["Rating"]),
        Field(title: "人脸检测", aliases: ["FacesDetected"])
    ]

    static func section(from properties: [String: Any]) -> MetadataSection? {
        guard isFujifilm(properties) else {
            return nil
        }

        let parsedMakerNote = makerNoteData(from: properties).flatMap(FujifilmMakerNoteParser.parse) ?? [:]
        let candidates = flatten(properties)
        var usedKeys = Set<String>()
        var usedTitles = Set<String>()
        var items: [MetadataItem] = []

        for field in fields {
            if let parsedValue = parsedMakerNote[field.title], !parsedValue.isEmpty {
                items.append(MetadataItem(id: "fujifilm-\(field.title)", key: field.title, value: parsedValue))
                usedTitles.insert(field.title)
                continue
            }

            guard let candidate = firstCandidate(for: field, in: candidates, usedKeys: usedKeys) else {
                continue
            }

            let readableValue = FujifilmMakerNoteParser.decodeFallbackValue(for: normalized(candidate.key), rawValue: candidate.value)
            guard !readableValue.isEmpty else {
                continue
            }

            usedKeys.insert(normalized(candidate.key))
            items.append(MetadataItem(id: "fujifilm-\(field.title)", key: field.title, value: readableValue))
            usedTitles.insert(field.title)
        }

        let extraParsedItems = parsedMakerNote
            .filter { !usedTitles.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { key, value in
                MetadataItem(id: "fujifilm-extra-\(key)", key: key, value: value)
            }

        items.append(contentsOf: extraParsedItems)

        if let makerFuji = properties[String(kCGImagePropertyMakerFujiDictionary)] as? [String: Any] {
            let extraSystemValues: [(key: String, value: String)] = makerFuji
                .map { rawKey, rawValue in
                    let key = MetadataKeyTranslator.chineseName(for: rawKey) ?? readableMakerFujiKey(rawKey)
                    let value = FujifilmMakerNoteParser.decodeFallbackValue(for: normalized(rawKey), rawValue: rawValue)
                    return (key: key, value: value)
                }
                .filter { !usedTitles.contains($0.key) && !$0.value.isEmpty }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            let extraSystemItems = extraSystemValues.map { pair in
                MetadataItem(id: "fujifilm-system-\(pair.key)", key: pair.key, value: pair.value)
            }

            items.append(contentsOf: extraSystemItems)
        }

        guard !items.isEmpty else {
            return nil
        }

        return MetadataSection(id: "fujifilm-parameters", title: "Fujifilm 参数", items: items)
    }

    private static func isFujifilm(_ properties: [String: Any]) -> Bool {
        if properties[String(kCGImagePropertyMakerFujiDictionary)] is [String: Any] {
            return true
        }

        return flatten(properties).contains { candidate in
            let key = normalized(candidate.key)
            guard (key.contains("make") || key.contains("model")),
                  let text = candidate.value as? String else {
                return false
            }

            return text.localizedCaseInsensitiveContains("fuji")
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
                .replacingOccurrences(of: "{MakerFuji}", with: "")
                .replacingOccurrences(of: "{Exif}", with: "")
                .replacingOccurrences(of: "{TIFF}", with: "")
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

    private static func readableMakerFujiKey(_ key: String) -> String {
        key.replacingOccurrences(of: "{MakerFuji}", with: "")
    }
}

nonisolated enum FujifilmMakerNoteParser {
    private enum Endian {
        case little
        case big
    }

    private struct ParsedTag {
        let name: String
        let title: String?
        let value: String
    }

    private static let typeSizes: [UInt16: Int] = [
        1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8
    ]

    private static let tagNames: [UInt16: String] = [
        0x1000: "Quality",
        0x1001: "Sharpness",
        0x1002: "WhiteBalance",
        0x1003: "Saturation",
        0x1004: "Contrast",
        0x1005: "ColorTemperature",
        0x1006: "Contrast",
        0x100a: "WhiteBalanceFineTune",
        0x100b: "NoiseReduction",
        0x100e: "HighISONoiseReduction",
        0x100f: "Clarity",
        0x1010: "FujiFlashMode",
        0x1011: "FlashExposureComp",
        0x1020: "Macro",
        0x1021: "FocusMode",
        0x1022: "AFMode",
        0x1023: "FocusPixel",
        0x1030: "SlowSync",
        0x1031: "PictureMode",
        0x1032: "ExposureCount",
        0x1033: "EXRAuto",
        0x1034: "EXRMode",
        0x1037: "MultipleExposure",
        0x1040: "ShadowTone",
        0x1041: "HighlightTone",
        0x1045: "LensModulationOptimizer",
        0x1047: "GrainEffectRoughness",
        0x1048: "ColorChromeEffect",
        0x1049: "BWAdjustment",
        0x104b: "BWMagentaGreen",
        0x104c: "GrainEffectSize",
        0x104e: "ColorChromeFXBlue",
        0x1050: "ShutterType",
        0x1100: "AutoBracketing",
        0x1101: "SequenceNumber",
        0x1102: "WhiteBalanceBracketing",
        0x1150: "CompositeImageMode",
        0x1201: "AdvancedFilter",
        0x1210: "ColorMode",
        0x1300: "BlurWarning",
        0x1301: "FocusWarning",
        0x1302: "ExposureWarning",
        0x1400: "DynamicRange",
        0x1401: "FilmMode",
        0x1402: "DynamicRangeSetting",
        0x1403: "DevelopmentDynamicRange",
        0x140b: "AutoDynamicRange",
        0x1422: "ImageStabilization",
        0x1425: "SceneRecognition",
        0x1431: "Rating",
        0x1436: "ImageGeneration",
        0x1438: "ImageCount",
        0x1443: "DRangePriority",
        0x1444: "DRangePriorityAuto",
        0x1445: "DRangePriorityFixed",
        0x4100: "FacesDetected"
    ]

    static func parse(_ data: Data) -> [String: String] {
        let offsets = candidateIFDOffsets(in: data)

        for endian in [Endian.little, .big] {
            for offset in offsets {
                let parsedTags = parseIFD(in: data, offset: offset, endian: endian)
                let fields = summarizedFields(from: parsedTags)

                if !fields.isEmpty {
                    return fields
                }
            }
        }

        return [:]
    }

    static func decodeFallbackValue(for normalizedKey: String, rawValue: Any) -> String {
        switch true {
        case matchesFujiKey(normalizedKey, aliases: ["filmmode", "filmsimulation", "filmsimulationmode"]):
            return mappedFallbackValue(rawValue, mapping: filmMode)
        case matchesFujiKey(normalizedKey, aliases: ["whitebalance", "whitebalancemode"]):
            return mappedFallbackValue(rawValue, mapping: whiteBalance)
        case matchesFujiKey(normalizedKey, aliases: ["whitebalancefinetune", "whitebalanceshift", "wbshift", "wbrblevels", "wbgrblevels"]):
            return fallbackWhiteBalanceShiftValue(rawValue) ?? MetadataParser.readableValue(rawValue)
        case matchesFujiKey(normalizedKey, aliases: ["colortemperature"]):
            return fallbackColorTemperatureValue(rawValue) ?? MetadataParser.readableValue(rawValue)
        case matchesFujiKey(normalizedKey, aliases: ["dynamicrange"]):
            return mappedFallbackValue(rawValue, mapping: dynamicRange)
        case matchesFujiKey(normalizedKey, aliases: ["dynamicrangesetting"]):
            return mappedFallbackValue(rawValue, mapping: dynamicRangeSetting)
        case matchesFujiKey(normalizedKey, aliases: ["drangepriority"]):
            return mappedFallbackValue(rawValue, mapping: dRangePriority)
        case matchesFujiKey(normalizedKey, aliases: ["drangepriorityauto", "drangepriorityfixed"]):
            return mappedFallbackValue(rawValue, mapping: dRangePriorityStrength)
        case matchesFujiKey(normalizedKey, aliases: ["advancedfilter"]):
            return mappedFallbackValue(rawValue, mapping: advancedFilter)
        case matchesFujiKey(normalizedKey, aliases: ["autobracketing"]):
            return mappedFallbackValue(rawValue, mapping: autoBracketing)
        case matchesFujiKey(normalizedKey, aliases: ["whitebalancebracketing"]):
            return mappedFallbackValue(rawValue, mapping: whiteBalanceBracketing)
        case matchesFujiKey(normalizedKey, aliases: ["clarity"]):
            return mappedFallbackValue(rawValue, mapping: clarity)
        case matchesFujiKey(normalizedKey, aliases: ["graineffectroughness"]):
            return mappedFallbackValue(rawValue, mapping: grainEffectRoughness)
        case matchesFujiKey(normalizedKey, aliases: ["graineffectsize"]):
            return mappedFallbackValue(rawValue, mapping: grainEffectSize)
        case matchesFujiKey(normalizedKey, aliases: ["colorchromeeffect"]):
            return mappedFallbackValue(rawValue, mapping: colorChromeEffect)
        case matchesFujiKey(normalizedKey, aliases: ["colorchromefxblue"]):
            return mappedFallbackValue(rawValue, mapping: colorChromeFXBlue)
        case matchesFujiKey(normalizedKey, aliases: ["highlighttone", "highlight", "highlights", "shadowtone", "shadow", "shadows"]):
            return mappedFallbackValue(rawValue, mapping: tone)
        case matchesFujiKey(normalizedKey, aliases: ["noisereduction", "highisonoisereduction"]):
            return mappedFallbackValue(rawValue, mapping: highISONoiseReduction)
        case matchesFujiKey(normalizedKey, aliases: ["shuttertype"]):
            return mappedFallbackValue(rawValue, mapping: shutterType)
        case matchesFujiKey(normalizedKey, aliases: ["picturemode"]):
            return mappedFallbackValue(rawValue, mapping: pictureMode)
        case matchesFujiKey(normalizedKey, aliases: ["multipleexposure"]):
            return mappedFallbackValue(rawValue, mapping: multipleExposure)
        case matchesFujiKey(normalizedKey, aliases: ["compositeimagemode"]):
            return mappedFallbackValue(rawValue, mapping: compositeImageMode)
        case matchesFujiKey(normalizedKey, aliases: ["scenerecognition"]):
            return mappedFallbackValue(rawValue, mapping: sceneRecognition)
        case matchesFujiKey(normalizedKey, aliases: ["imagegeneration"]):
            return mappedFallbackValue(rawValue, mapping: imageGeneration)
        case matchesFujiKey(normalizedKey, aliases: ["lensmodulationoptimizer"]):
            return mappedFallbackValue(rawValue, mapping: offOn)
        case matchesFujiKey(normalizedKey, aliases: ["imagestabilization"]):
            return fallbackImageStabilizationValue(rawValue) ?? MetadataParser.readableValue(rawValue)
        default:
            return MetadataParser.readableValue(rawValue)
        }
    }

    private static func candidateIFDOffsets(in data: Data) -> [Int] {
        var offsets: [Int] = []

        if data.starts(with: Data("FUJIFILM".utf8)) {
            if let offset = readUInt32(data, at: 8, endian: .little) {
                offsets.append(Int(offset))
            }

            if let offset = readUInt32(data, at: 8, endian: .big) {
                offsets.append(Int(offset))
            }

            if let offset = readUInt32(data, at: 12, endian: .little) {
                offsets.append(Int(offset))
            }

            offsets.append(contentsOf: [12, 8])
        } else {
            offsets.append(0)
        }

        var seenOffsets = Set<Int>()
        return offsets.filter { offset in
            guard offset >= 0, offset + 2 <= data.count else {
                return false
            }

            return seenOffsets.insert(offset).inserted
        }
    }

    private static func parseIFD(in data: Data, offset: Int, endian: Endian) -> [ParsedTag] {
        guard let entryCountValue = readUInt16(data, at: offset, endian: endian) else {
            return []
        }

        let entryCount = Int(entryCountValue)
        guard entryCount > 0, entryCount < 512, offset + 2 + entryCount * 12 <= data.count else {
            return []
        }

        var parsedTags: [ParsedTag] = []

        for index in 0..<entryCount {
            let entryOffset = offset + 2 + index * 12
            guard
                let tag = readUInt16(data, at: entryOffset, endian: endian),
                let type = readUInt16(data, at: entryOffset + 2, endian: endian),
                let countValue = readUInt32(data, at: entryOffset + 4, endian: endian),
                let typeSize = typeSizes[type],
                let tagName = tagNames[tag]
            else {
                continue
            }

            let count = Int(countValue)
            guard count > 0, count <= 1024 else {
                continue
            }

            let byteCount = typeSize * count
            guard let valueData = valueData(in: data, entryOffset: entryOffset, byteCount: byteCount, endian: endian),
                  let parsed = parsedTag(tag, name: tagName, type: type, count: count, valueData: valueData, endian: endian) else {
                continue
            }

            parsedTags.append(parsed)
        }

        return parsedTags
    }

    private static func valueData(in data: Data, entryOffset: Int, byteCount: Int, endian: Endian) -> Data? {
        guard byteCount > 0 else {
            return nil
        }

        if byteCount <= 4 {
            let range = entryOffset + 8..<(entryOffset + 8 + byteCount)
            guard range.upperBound <= data.count else {
                return nil
            }

            return data.subdata(in: range)
        }

        guard let valueOffset = readUInt32(data, at: entryOffset + 8, endian: endian) else {
            return nil
        }

        let start = Int(valueOffset)
        let range = start..<(start + byteCount)
        guard start >= 0, range.upperBound <= data.count else {
            return nil
        }

        return data.subdata(in: range)
    }

    private static func parsedTag(
        _ tag: UInt16,
        name: String,
        type: UInt16,
        count: Int,
        valueData: Data,
        endian: Endian
    ) -> ParsedTag? {
        let values = numericValues(type: type, count: count, valueData: valueData, endian: endian)
        let strings = stringValue(type: type, valueData: valueData)
        let rationals = rationalValues(type: type, count: count, valueData: valueData, endian: endian)
        let value: String?
        let title: String?

        switch tag {
        case 0x1000:
            title = "图像质量"
            value = strings
        case 0x1001:
            title = "锐度"
            value = mappedValue(values.first, mapping: sharpness)
        case 0x1002:
            title = "白平衡"
            value = mappedValue(values.first, mapping: whiteBalance)
        case 0x1003:
            title = "色彩"
            value = mappedValue(values.first, mapping: saturation)
        case 0x1004:
            title = nil
            value = mappedValue(values.first, mapping: contrast)
        case 0x1005:
            title = "色温"
            value = values.first.map { "\($0) K" }
        case 0x1006:
            title = "对比度"
            value = mappedValue(values.first, mapping: contrastSimple)
        case 0x100a:
            title = "白平衡偏移"
            value = values.count >= 2 ? "R \(formattedSigned(values[0])), B \(formattedSigned(values[1]))" : nil
        case 0x100b:
            title = "降噪"
            value = mappedValue(values.first, mapping: noiseReduction)
        case 0x100e:
            title = "降噪"
            value = mappedValue(values.first, mapping: highISONoiseReduction)
        case 0x100f:
            title = "清晰度"
            value = mappedValue(values.first, mapping: clarity)
        case 0x1010:
            title = "闪光灯"
            value = mappedValue(values.first, mapping: fujiFlashMode)
        case 0x1011:
            title = "闪光灯"
            value = rationals.first.map { "闪光灯曝光补偿: \($0)" }
        case 0x1020:
            title = "对焦模式"
            value = mappedValue(values.first, mapping: offOn)
        case 0x1021:
            title = "对焦模式"
            value = mappedValue(values.first, mapping: focusMode)
        case 0x1022:
            title = "对焦模式"
            value = mappedValue(values.first, mapping: afMode)
        case 0x1023:
            title = "对焦模式"
            value = values.count >= 2 ? "\(values[0]), \(values[1])" : nil
        case 0x1030:
            title = "闪光灯"
            value = mappedValue(values.first, mapping: offOn).map { "慢速同步: \($0)" }
        case 0x1031:
            title = "拍摄模式"
            value = mappedValue(values.first, mapping: pictureMode)
        case 0x1032:
            title = "拍摄模式"
            value = values.first.map { "多张合成张数: \($0)" }
        case 0x1033:
            title = "EXR 模式"
            value = mappedValue(values.first, mapping: exrAuto)
        case 0x1034:
            title = "EXR 模式"
            value = mappedValue(values.first, mapping: exrMode)
        case 0x1037:
            title = "拍摄模式"
            value = mappedValue(values.first, mapping: multipleExposure)
        case 0x1040:
            title = "阴影"
            value = mappedValue(values.first, mapping: tone)
        case 0x1041:
            title = "高光"
            value = mappedValue(values.first, mapping: tone)
        case 0x1045:
            title = "镜头像差校正"
            value = mappedValue(values.first, mapping: offOn)
        case 0x1047:
            title = "颗粒效果"
            value = mappedValue(values.first, mapping: grainEffectRoughness)
        case 0x1048:
            title = "胶片颗粒/色彩效果"
            value = mappedValue(values.first, mapping: colorChromeEffect)
        case 0x1049:
            title = "胶片颗粒/色彩效果"
            value = signedByteValue(type: type, valueData: valueData).map { "黑白暖冷: \(formattedSigned($0))" }
        case 0x104b:
            title = "胶片颗粒/色彩效果"
            value = signedByteValue(type: type, valueData: valueData).map { "黑白洋红/绿色: \(formattedSigned($0))" }
        case 0x104c:
            title = "颗粒效果"
            value = mappedValue(values.first, mapping: grainEffectSize)
        case 0x104e:
            title = "胶片颗粒/色彩效果"
            value = mappedValue(values.first, mapping: colorChromeFXBlue)
        case 0x1050:
            title = "拍摄模式"
            value = mappedValue(values.first, mapping: shutterType)
        case 0x1100:
            title = "包围曝光"
            value = mappedValue(values.first, mapping: autoBracketing)
        case 0x1101:
            title = "拍摄模式"
            value = values.first.map { "序列号: \($0)" }
        case 0x1102:
            title = "包围曝光"
            value = mappedValue(values.first, mapping: whiteBalanceBracketing)
        case 0x1150:
            title = "拍摄模式"
            value = mappedValue(values.first, mapping: compositeImageMode)
        case 0x1201:
            title = "高级滤镜"
            value = mappedValue(values.first, mapping: advancedFilter)
        case 0x1210:
            title = "色彩"
            value = mappedValue(values.first, mapping: colorMode)
        case 0x1300:
            title = "拍摄警告"
            value = mappedValue(values.first, mapping: blurWarning)
        case 0x1301:
            title = "拍摄警告"
            value = mappedValue(values.first, mapping: focusWarning)
        case 0x1302:
            title = "拍摄警告"
            value = mappedValue(values.first, mapping: exposureWarning)
        case 0x1400:
            title = "动态范围"
            value = mappedValue(values.first, mapping: dynamicRange)
        case 0x1401:
            title = "胶片风格"
            value = mappedValue(values.first, mapping: filmMode)
        case 0x1402:
            title = "动态范围"
            value = mappedValue(values.first, mapping: dynamicRangeSetting)
        case 0x1403:
            title = "机内处理"
            value = values.first.map { "\($0)%" }
        case 0x140b:
            title = "动态范围"
            value = values.first.map { "\($0)%" }
        case 0x1422:
            title = "防抖"
            value = imageStabilizationDescription(values)
        case 0x1425:
            title = "拍摄模式"
            value = mappedValue(values.first, mapping: sceneRecognition)
        case 0x1431:
            title = "评分"
            value = values.first.map(String.init)
        case 0x1436:
            title = "机内处理"
            value = mappedValue(values.first, mapping: imageGeneration)
        case 0x1438:
            title = "快门次数"
            value = values.first.map { "\($0 & 0x7fff)" }
        case 0x1443:
            title = "机内处理"
            value = mappedValue(values.first, mapping: dRangePriority).map { "动态范围优先: \($0)" }
        case 0x1444:
            title = "机内处理"
            value = mappedValue(values.first, mapping: dRangePriorityStrength)
        case 0x1445:
            title = "机内处理"
            value = mappedValue(values.first, mapping: dRangePriorityStrength)
        case 0x4100:
            title = "人脸检测"
            value = values.first.map { "\($0) 张脸" }
        default:
            title = nil
            value = nil
        }

        guard let value, !value.isEmpty else {
            return nil
        }

        return ParsedTag(name: name, title: title, value: value)
    }

    private static func summarizedFields(from tags: [ParsedTag]) -> [String: String] {
        var fields: [String: String] = [:]

        for tag in tags {
            let title = tag.title ?? tag.name
            let component = tag.name == title ? tag.value : "\(tag.name): \(tag.value)"

            if let existing = fields[title] {
                fields[title] = "\(existing)\n\(component)"
            } else {
                fields[title] = component
            }
        }

        return fields
    }

    private static func numericValues(type: UInt16, count: Int, valueData: Data, endian: Endian) -> [Int] {
        switch type {
        case 1, 7:
            return valueData.prefix(count).map(Int.init)
        case 2:
            return []
        case 3:
            return (0..<count).compactMap { index in
                readUInt16(valueData, at: index * 2, endian: endian).map(Int.init)
            }
        case 4:
            return (0..<count).compactMap { index in
                readUInt32(valueData, at: index * 4, endian: endian).map(Int.init)
            }
        case 9:
            return (0..<count).compactMap { index in
                readInt32(valueData, at: index * 4, endian: endian).map(Int.init)
            }
        default:
            return []
        }
    }

    private static func stringValue(type: UInt16, valueData: Data) -> String? {
        guard type == 2 else {
            return nil
        }

        let bytes = valueData.prefix { $0 != 0 }
        guard !bytes.isEmpty else {
            return nil
        }

        return String(data: Data(bytes), encoding: .ascii)
    }

    private static func signedByteValue(type: UInt16, valueData: Data) -> Int? {
        guard !valueData.isEmpty else {
            return nil
        }

        if type == 6 || type == 1 {
            return Int(Int8(bitPattern: valueData[0]))
        }

        return nil
    }

    private static func rationalValues(type: UInt16, count: Int, valueData: Data, endian: Endian) -> [String] {
        switch type {
        case 5:
            return (0..<count).compactMap { index in
                let offset = index * 8
                guard
                    let numerator = readUInt32(valueData, at: offset, endian: endian),
                    let denominator = readUInt32(valueData, at: offset + 4, endian: endian),
                    denominator != 0
                else {
                    return nil
                }

                return formatRational(Double(numerator) / Double(denominator))
            }
        case 10:
            return (0..<count).compactMap { index in
                let offset = index * 8
                guard
                    let numerator = readInt32(valueData, at: offset, endian: endian),
                    let denominator = readInt32(valueData, at: offset + 4, endian: endian),
                    denominator != 0
                else {
                    return nil
                }

                return formatRational(Double(numerator) / Double(denominator))
            }
        default:
            return []
        }
    }

    private static func formatRational(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.2f", value)
    }

    private static func formattedSigned(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }

    private static func imageStabilizationDescription(_ values: [Int]) -> String? {
        guard !values.isEmpty else {
            return nil
        }

        var parts: [String] = []
        if let mode = imageStabilizationType[values[0]] {
            parts.append(mode)
        }

        if values.count > 1, let status = imageStabilizationStatus[values[1]] {
            parts.append(status)
        }

        if values.count > 2, values[2] != 0 {
            parts.append("附加值: \(values[2])")
        }

        return parts.isEmpty ? values.map(String.init).joined(separator: ", ") : parts.joined(separator: ", ")
    }

    private static func mappedFallbackValue(_ rawValue: Any, mapping: [Int: String]) -> String {
        guard let number = firstFallbackInteger(from: rawValue) else {
            return MetadataParser.readableValue(rawValue)
        }

        return mapping[number] ?? String(number)
    }

    private static func firstFallbackInteger(from rawValue: Any) -> Int? {
        switch rawValue {
        case let number as NSNumber:
            return number.intValue
        case let array as [NSNumber]:
            return array.first?.intValue
        case let array as [Int]:
            return array.first
        case let array as [Any]:
            return array.compactMap { firstFallbackInteger(from: $0) }.first
        default:
            return nil
        }
    }

    private static func fallbackIntegerArray(from rawValue: Any) -> [Int]? {
        switch rawValue {
        case let number as NSNumber:
            return [number.intValue]
        case let array as [NSNumber]:
            return array.map(\.intValue)
        case let array as [Int]:
            return array
        case let array as [Any]:
            let values = array.compactMap { firstFallbackInteger(from: $0) }
            return values.isEmpty ? nil : values
        default:
            return nil
        }
    }

    private static func fallbackWhiteBalanceShiftValue(_ rawValue: Any) -> String? {
        guard let values = fallbackIntegerArray(from: rawValue), values.count >= 2 else {
            return nil
        }

        if values.count >= 4 {
            return "G1 \(formattedSigned(values[0])), R \(formattedSigned(values[1])), B \(formattedSigned(values[2])), G2 \(formattedSigned(values[3]))"
        }

        return "R \(formattedSigned(values[0])), B \(formattedSigned(values[1]))"
    }

    private static func fallbackColorTemperatureValue(_ rawValue: Any) -> String? {
        guard let value = firstFallbackInteger(from: rawValue) else {
            return nil
        }

        return "\(value) K"
    }

    private static func fallbackImageStabilizationValue(_ rawValue: Any) -> String? {
        guard let values = fallbackIntegerArray(from: rawValue), !values.isEmpty else {
            return nil
        }

        return imageStabilizationDescription(values)
    }

    private static func matchesFujiKey(_ normalizedKey: String, aliases: [String]) -> Bool {
        aliases.contains { alias in
            normalizedKey == alias || normalizedKey.hasSuffix(alias) || normalizedKey.contains(alias)
        }
    }

    private static func mappedValue(_ value: Int?, mapping: [Int: String]) -> String? {
        guard let value else {
            return nil
        }

        return mapping[value] ?? String(format: "0x%04x", value)
    }

    private static func readUInt16(_ data: Data, at offset: Int, endian: Endian) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else {
            return nil
        }

        let bytes = [data[offset], data[offset + 1]]
        switch endian {
        case .little:
            return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        case .big:
            return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        }
    }

    private static func readUInt32(_ data: Data, at offset: Int, endian: Endian) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else {
            return nil
        }

        let bytes = [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]]
        switch endian {
        case .little:
            return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        case .big:
            return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        }
    }

    private static func readInt32(_ data: Data, at offset: Int, endian: Endian) -> Int32? {
        readUInt32(data, at: offset, endian: endian).map { Int32(bitPattern: $0) }
    }

    private static let sharpness = [0x01: "Soft", 0x02: "Soft2", 0x03: "Normal", 0x04: "Hard", 0x05: "Hard2", 0x82: "Medium Soft", 0x84: "Medium Hard", 0x8000: "Film Simulation", 0xffff: "n/a"]
    private static let whiteBalance = [0x000: "Auto", 0x001: "Auto (white priority)", 0x002: "Auto (ambiance priority)", 0x100: "Daylight", 0x200: "Cloudy", 0x300: "Daylight Fluorescent", 0x301: "Day White Fluorescent", 0x302: "White Fluorescent", 0x303: "Warm White Fluorescent", 0x304: "Living Room Warm White Fluorescent", 0x400: "Incandescent", 0x500: "Flash", 0x600: "Underwater", 0xf00: "Custom", 0xf01: "Custom2", 0xf02: "Custom3", 0xf03: "Custom4", 0xf04: "Custom5", 0xff0: "Kelvin"]
    private static let saturation = [0x000: "0 (normal)", 0x080: "+1 (medium high)", 0x100: "+2 (high)", 0x0c0: "+3 (very high)", 0x0e0: "+4 (highest)", 0x180: "-1 (medium low)", 0x200: "Low", 0x300: "None (B&W)", 0x301: "B&W Red Filter", 0x302: "B&W Yellow Filter", 0x303: "B&W Green Filter", 0x310: "B&W Sepia", 0x400: "-2 (low)", 0x4c0: "-3 (very low)", 0x4e0: "-4 (lowest)", 0x500: "Acros", 0x501: "Acros Red Filter", 0x502: "Acros Yellow Filter", 0x503: "Acros Green Filter", 0x8000: "Film Simulation"]
    private static let contrast = [0x000: "Normal", 0x080: "Medium High", 0x100: "High", 0x180: "Medium Low", 0x200: "Low", 0x8000: "Film Simulation"]
    private static let contrastSimple = [0x000: "Normal", 0x100: "High", 0x300: "Low"]
    private static let noiseReduction = [0x40: "Low", 0x80: "Normal", 0x100: "n/a"]
    private static let highISONoiseReduction = [0x000: "0 (normal)", 0x100: "+2 (strong)", 0x180: "+1 (medium strong)", 0x1c0: "+3 (very strong)", 0x1e0: "+4 (strongest)", 0x200: "-2 (weak)", 0x280: "-1 (medium weak)", 0x2c0: "-3 (very weak)", 0x2e0: "-4 (weakest)"]
    private static let clarity = [-5000: "-5", -4000: "-4", -3000: "-3", -2000: "-2", -1000: "-1", 0: "0", 1000: "1", 2000: "2", 3000: "3", 4000: "4", 5000: "5"]
    private static let offOn = [0: "Off", 1: "On"]
    private static let fujiFlashMode = [0: "Auto", 1: "On", 2: "Off", 3: "Red-eye reduction", 4: "External", 16: "Commander", 0x8000: "Not Attached", 0x8120: "TTL", 0x8320: "TTL Auto - Did not fire", 0x9840: "Manual", 0x9860: "Flash Commander", 0x9880: "Multi-flash", 0xa920: "1st Curtain (front)", 0xaa20: "TTL Slow - 1st Curtain (front)", 0xab20: "TTL Auto - 1st Curtain (front)", 0xad20: "TTL - Red-eye Flash - 1st Curtain (front)", 0xae20: "TTL Slow - Red-eye Flash - 1st Curtain (front)", 0xaf20: "TTL Auto - Red-eye Flash - 1st Curtain (front)", 0xc920: "2nd Curtain (rear)", 0xca20: "TTL Slow - 2nd Curtain (rear)", 0xcb20: "TTL Auto - 2nd Curtain (rear)", 0xcd20: "TTL - Red-eye Flash - 2nd Curtain (rear)", 0xce20: "TTL Slow - Red-eye Flash - 2nd Curtain (rear)", 0xcf20: "TTL Auto - Red-eye Flash - 2nd Curtain (rear)", 0xe920: "High Speed Sync (HSS)"]
    private static let focusMode = [0: "Auto", 1: "Manual", 65535: "Movie"]
    private static let afMode = [0: "No", 1: "Single Point", 256: "Zone", 512: "Wide/Tracking"]
    private static let pictureMode = [0x000: "Auto", 0x001: "Portrait", 0x002: "Landscape", 0x003: "Macro", 0x004: "Sports", 0x005: "Night Scene", 0x006: "Program AE", 0x007: "Natural Light", 0x008: "Anti-blur", 0x009: "Beach & Snow", 0x00a: "Sunset", 0x00b: "Museum", 0x00c: "Party", 0x00d: "Flower", 0x00e: "Text", 0x00f: "Natural Light & Flash", 0x010: "Beach", 0x011: "Snow", 0x012: "Fireworks", 0x013: "Underwater", 0x014: "Portrait with Skin Correction", 0x016: "Panorama", 0x017: "Night (tripod)", 0x018: "Pro Low-light", 0x019: "Pro Focus", 0x01a: "Portrait 2", 0x01b: "Dog Face Detection", 0x01c: "Cat Face Detection", 0x030: "HDR", 0x040: "Advanced Filter", 0x100: "Aperture-priority AE", 0x200: "Shutter speed priority AE", 0x300: "Manual"]
    private static let exrAuto = [0: "Auto", 1: "Manual"]
    private static let exrMode = [0x100: "HR (High Resolution)", 0x200: "SN (Signal to Noise priority)", 0x300: "DR (Dynamic Range priority)"]
    private static let multipleExposure = [1: "Additive", 2: "Average", 3: "Light", 4: "Dark"]
    private static let compositeImageMode = [0: "n/a", 1: "Pro Low-light", 2: "Pro Focus", 32: "Panorama", 128: "HDR", 1024: "Multi-exposure"]
    private static let tone = [-64: "+4 (hardest)", -48: "+3 (very hard)", -32: "+2 (hard)", -16: "+1 (medium hard)", 0: "0 (normal)", 16: "-1 (medium soft)", 32: "-2 (soft)"]
    private static let grainEffectRoughness = [0: "Off", 32: "Weak", 64: "Strong"]
    private static let colorChromeEffect = [0: "Off", 32: "Weak", 64: "Strong"]
    private static let grainEffectSize = [0: "Off", 16: "Small", 32: "Large"]
    private static let colorChromeFXBlue = [0: "Off", 32: "Weak", 64: "Strong"]
    private static let shutterType = [0: "Mechanical", 1: "Electronic", 2: "Electronic (long shutter speed)", 3: "Electronic Front Curtain"]
    private static let autoBracketing = [0: "Off", 1: "On", 2: "No flash & flash", 6: "Pixel Shift"]
    private static let whiteBalanceBracketing = [0x01ff: "+/- 1", 0x02ff: "+/- 2", 0x03ff: "+/- 3"]
    private static let advancedFilter = [0x10000: "Pop Color", 0x20000: "Hi Key", 0x30000: "Toy Camera", 0x40000: "Miniature", 0x50000: "Dynamic Tone", 0x60001: "Partial Color Red", 0x60002: "Partial Color Yellow", 0x60003: "Partial Color Green", 0x60004: "Partial Color Blue", 0x60005: "Partial Color Orange", 0x60006: "Partial Color Purple", 0x70000: "Soft Focus", 0x90000: "Low Key", 0x100000: "Light Leak", 0x130000: "Expired Film Green", 0x130001: "Expired Film Red", 0x130002: "Expired Film Neutral"]
    private static let colorMode = [0x00: "Standard", 0x10: "Chrome", 0x30: "B & W"]
    private static let blurWarning = [0: "None", 1: "Blur Warning"]
    private static let focusWarning = [0: "Good", 1: "Out of focus"]
    private static let exposureWarning = [0: "Good", 1: "Bad exposure"]
    private static let dynamicRange = [1: "Standard", 3: "Wide"]
    private static let filmMode = [0x000: "F0/Standard (Provia)", 0x100: "F1/Studio Portrait", 0x110: "F1a/Studio Portrait Enhanced Saturation", 0x120: "F1b/Studio Portrait Smooth Skin Tone (Astia)", 0x130: "F1c/Studio Portrait Increased Sharpness", 0x200: "F2/Fujichrome (Velvia)", 0x300: "F3/Studio Portrait Ex", 0x400: "F4/Velvia", 0x500: "Pro Neg. Std", 0x501: "Pro Neg. Hi", 0x600: "Classic Chrome", 0x700: "Eterna", 0x800: "Classic Negative", 0x900: "Bleach Bypass", 0xa00: "Nostalgic Neg", 0xb00: "Reala ACE"]
    private static let dynamicRangeSetting = [0x000: "Auto", 0x001: "Manual", 0x100: "Standard (100%)", 0x200: "Wide1 (230%)", 0x201: "Wide2 (400%)", 0x8000: "Film Simulation"]
    private static let imageGeneration = [0: "Original Image", 1: "Re-developed from RAW"]
    private static let imageStabilizationType = [0: "None", 1: "Optical", 2: "Sensor-shift", 3: "OIS Lens", 258: "IBIS/OIS + DIS", 512: "Digital"]
    private static let imageStabilizationStatus = [0: "Off", 1: "On (mode 1, continuous)", 2: "On (mode 2, shooting only)"]
    private static let sceneRecognition = [0: "Unrecognized", 0x100: "Portrait Image", 0x103: "Night Portrait", 0x105: "Backlit Portrait", 0x200: "Landscape Image", 0x300: "Night Scene", 0x400: "Macro"]
    private static let dRangePriority = [0: "Auto", 1: "Fixed"]
    private static let dRangePriorityStrength = [1: "Weak", 2: "Strong", 3: "Plus"]
}
