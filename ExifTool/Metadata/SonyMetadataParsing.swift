//
//  SonyMetadataParsing.swift
//  ExifTool
//
//  Created by Codex on 2026/4/24.
//

import Foundation
import ImageIO

nonisolated enum SonyMetadataExtractor {
    private struct Field {
        let title: String
        let aliases: [String]
    }

    private struct Candidate {
        let key: String
        let value: Any
    }

    private enum Group: CaseIterable {
        case exposure
        case color
        case focusDrive
        case cameraLens

        var id: String {
            switch self {
            case .exposure:
                return "sony-group-exposure"
            case .color:
                return "sony-group-color"
            case .focusDrive:
                return "sony-group-focus-drive"
            case .cameraLens:
                return "sony-group-camera-lens"
            }
        }

        var title: String {
            switch self {
            case .exposure:
                return "SONY 曝光/画质"
            case .color:
                return "SONY 色彩/白平衡"
            case .focusDrive:
                return "SONY 对焦/驱动"
            case .cameraLens:
                return "SONY 机身/镜头"
            }
        }
    }

    private static let fields: [Field] = [
        Field(title: "SONY 型号 ID", aliases: ["SonyModelID"]),
        Field(title: "文件格式", aliases: ["FileFormat"]),
        Field(title: "序列号", aliases: ["SerialNumber"]),
        Field(title: "图像质量", aliases: ["Quality", "JPEGQuality", "Quality2", "RAWFileType"]),
        Field(title: "JPEG/HEIF", aliases: ["JPEG-HEIFSwitch", "JPEGHEIFSwitch"]),
        Field(title: "图像尺寸", aliases: ["SonyImageSize", "FullImageSize", "PreviewImageSize"]),
        Field(title: "宽高比", aliases: ["AspectRatio"]),
        Field(title: "评分", aliases: ["Rating"]),
        Field(title: "曝光模式", aliases: ["ExposureMode", "ExposureProgram"]),
        Field(title: "测光模式", aliases: ["MeteringMode", "MeteringMode2"]),
        Field(title: "曝光补偿", aliases: ["ExposureStandardAdjustment", "FlashExposureComp", "FlashLevel"]),
        Field(title: "HDR", aliases: ["HDR"]),
        Field(title: "动态范围优化", aliases: ["DynamicRangeOptimizer"]),
        Field(title: "长曝光降噪", aliases: ["LongExposureNoiseReduction"]),
        Field(title: "高 ISO 降噪", aliases: ["HighISONoiseReduction", "HighISONoiseReduction2", "MultiFrameNoiseReduction", "MultiFrameNREffect"]),
        Field(title: "白平衡", aliases: ["WhiteBalance", "PrioritySetInAWB"]),
        Field(title: "白平衡偏移", aliases: ["WBShiftAB_GM", "WBShiftAB_GM_Precise", "WhiteBalanceFineTune"]),
        Field(title: "色温", aliases: ["ColorTemperature", "ColorTemperatureSetting"]),
        Field(title: "色彩补偿滤镜", aliases: ["ColorCompensationFilter", "ColorCompensationFilterSet"]),
        Field(title: "创意风格", aliases: ["CreativeStyle", "ColorMode"]),
        Field(title: "照片效果", aliases: ["PictureEffect", "SoftSkinEffect"]),
        Field(title: "对比度", aliases: ["Contrast"]),
        Field(title: "饱和度", aliases: ["Saturation"]),
        Field(title: "锐度", aliases: ["Sharpness", "SharpnessRange"]),
        Field(title: "阴影", aliases: ["Shadows"]),
        Field(title: "高光", aliases: ["Highlights"]),
        Field(title: "清晰度", aliases: ["Clarity"]),
        Field(title: "淡化", aliases: ["Fade"]),
        Field(title: "场景模式", aliases: ["SceneMode", "IntelligentAuto"]),
        Field(title: "对焦模式", aliases: ["FocusMode"]),
        Field(title: "AF 区域模式", aliases: ["AFAreaMode", "AFAreaModeSetting"]),
        Field(title: "AF 辅助灯", aliases: ["AFIlluminator"]),
        Field(title: "AF 点", aliases: ["AFPointSelected", "FlexibleSpotPosition", "FocusLocation", "FocusLocation2"]),
        Field(title: "AF 跟踪", aliases: ["AFTracking"]),
        Field(title: "闪光灯", aliases: ["FlashAction", "FlashStatus", "FlashMode"]),
        Field(title: "释放模式", aliases: ["ReleaseMode", "ReleaseMode2"]),
        Field(title: "连拍", aliases: ["SequenceNumber", "SequenceImageNumber", "SequenceFileNumber", "SequenceLength"]),
        Field(title: "防抖", aliases: ["ImageStabilization", "Anti-Blur", "SteadyShot"]),
        Field(title: "电子前帘快门", aliases: ["ElectronicFrontCurtainShutter"]),
        Field(title: "快门次数", aliases: ["ShutterCount", "ShutterCount2", "ShotNumberSincePowerUp"]),
        Field(title: "镜头类型", aliases: ["LensType"]),
        Field(title: "镜头规格", aliases: ["LensSpec"]),
        Field(title: "镜头卡口", aliases: ["LensMount"]),
        Field(title: "增距镜", aliases: ["Teleconverter"]),
        Field(title: "微距", aliases: ["Macro"]),
        Field(title: "自动人像构图", aliases: ["AutoPortraitFramed"]),
        Field(title: "裁切模式", aliases: ["StepCropShooting"]),
        Field(title: "镜头校正", aliases: ["VignettingCorrection", "LateralChromaticAberration", "DistortionCorrectionSetting"])
    ]

    static func sections(from properties: [String: Any], imageData: Data? = nil) -> [MetadataSection] {
        guard isSony(properties, imageData: imageData) else {
            return []
        }

        let parsedMakerNoteData = makerNoteData(from: properties) ?? imageData.flatMap(jpegMakerNoteData)
        let parsedMakerNote = parsedMakerNoteData.flatMap(SonyMakerNoteParser.parse) ?? [:]
        let candidates = flatten(properties)
        var usedKeys = Set<String>()
        var usedTitles = Set<String>()
        var items: [MetadataItem] = []

        for field in fields {
            if let parsedValue = parsedMakerNote[field.title], !parsedValue.isEmpty {
                items.append(MetadataItem(id: "sony-\(field.title)", key: field.title, value: parsedValue))
                usedTitles.insert(field.title)
                continue
            }

            guard let candidate = firstCandidate(for: field, in: candidates, usedKeys: usedKeys) else {
                continue
            }

            let readableValue = SonyMakerNoteParser.decodeFallbackValue(for: normalized(candidate.key), rawValue: candidate.value)
            guard !readableValue.isEmpty else {
                continue
            }

            usedKeys.insert(normalized(candidate.key))
            items.append(MetadataItem(id: "sony-\(field.title)", key: field.title, value: readableValue))
            usedTitles.insert(field.title)
        }

        let extraItems = parsedMakerNote
            .filter { !usedTitles.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { MetadataItem(id: "sony-extra-\($0.key)", key: $0.key, value: $0.value) }

        items.append(contentsOf: extraItems)

        guard !items.isEmpty else {
            return []
        }

        return [groupedSection(from: items)]
    }

    private static func groupedSection(from items: [MetadataItem]) -> MetadataSection {
        var groupedItems = Dictionary(uniqueKeysWithValues: Group.allCases.map { ($0, [MetadataItem]()) })

        for item in items {
            groupedItems[group(for: item.key), default: []].append(item)
        }

        let itemGroups = Group.allCases.compactMap { group -> MetadataItemGroup? in
            guard let items = groupedItems[group], !items.isEmpty else {
                return nil
            }

            return MetadataItemGroup(id: group.id, title: group.title, items: items)
        }

        return MetadataSection(id: "sony-parameters", title: "SONY 参数", items: items, itemGroups: itemGroups)
    }

    private static func group(for key: String) -> Group {
        switch key {
        case "白平衡", "白平衡偏移", "色温", "色彩补偿滤镜", "创意风格", "照片效果", "对比度", "饱和度", "锐度", "阴影", "高光", "清晰度", "淡化", "场景模式":
            return .color
        case "对焦模式", "AF 区域模式", "AF 辅助灯", "AF 点", "AF 跟踪", "闪光灯", "释放模式", "连拍", "电子前帘快门", "微距", "自动人像构图":
            return .focusDrive
        case "SONY 型号 ID", "文件格式", "序列号", "镜头类型", "镜头规格", "镜头卡口", "增距镜", "裁切模式", "镜头校正":
            return .cameraLens
        default:
            return .exposure
        }
    }

    private static func isSony(_ properties: [String: Any], imageData: Data?) -> Bool {
        if let makerNote = makerNoteData(from: properties), SonyMakerNoteParser.hasSonyHeader(makerNote) {
            return true
        }

        if let imageData, let makerNote = jpegMakerNoteData(from: imageData), SonyMakerNoteParser.hasSonyHeader(makerNote) {
            return true
        }

        return flatten(properties).contains { candidate in
            let key = normalized(candidate.key)
            guard (key.contains("make") || key.contains("model")),
                  let text = candidate.value as? String else {
                return false
            }

            return text.localizedCaseInsensitiveContains("sony")
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

    private static func jpegMakerNoteData(from data: Data) -> Data? {
        guard data.count > 4, data[0] == 0xff, data[1] == 0xd8 else {
            return nil
        }

        var offset = 2
        while offset + 4 <= data.count {
            guard data[offset] == 0xff else {
                return nil
            }

            var markerOffset = offset
            while markerOffset < data.count, data[markerOffset] == 0xff {
                markerOffset += 1
            }

            guard markerOffset < data.count else {
                return nil
            }

            let marker = data[markerOffset]
            offset = markerOffset + 1

            if marker == 0xda || marker == 0xd9 {
                return nil
            }

            guard offset + 2 <= data.count,
                  let segmentLengthValue = readUInt16(data, at: offset, endian: .big) else {
                return nil
            }

            let segmentLength = Int(segmentLengthValue)
            let segmentStart = offset + 2
            let segmentEnd = offset + segmentLength
            guard segmentLength >= 2, segmentEnd <= data.count else {
                return nil
            }

            if marker == 0xe1 {
                let segment = data.subdata(in: segmentStart..<segmentEnd)
                if let makerNote = exifMakerNoteData(fromAPP1Segment: segment) {
                    return makerNote
                }
            }

            offset = segmentEnd
        }

        return nil
    }

    private static func exifMakerNoteData(fromAPP1Segment segment: Data) -> Data? {
        let exifHeader = Data([0x45, 0x78, 0x69, 0x66, 0x00, 0x00])
        guard segment.starts(with: exifHeader) else {
            return nil
        }

        let tiffStart = exifHeader.count
        guard tiffStart + 8 <= segment.count else {
            return nil
        }

        let endian: TIFFEndian
        switch (segment[tiffStart], segment[tiffStart + 1]) {
        case (0x49, 0x49):
            endian = .little
        case (0x4d, 0x4d):
            endian = .big
        default:
            return nil
        }

        guard readUInt16(segment, at: tiffStart + 2, endian: endian) == 42,
              let firstIFDOffset = readUInt32(segment, at: tiffStart + 4, endian: endian),
              let exifIFDOffset = ifdEntryValue(forTag: 0x8769, in: segment, tiffStart: tiffStart, ifdOffset: Int(firstIFDOffset), endian: endian) else {
            return nil
        }

        return ifdDataValue(forTag: 0x927c, in: segment, tiffStart: tiffStart, ifdOffset: exifIFDOffset, endian: endian)
    }

    private typealias TIFFEndian = TIFFByteOrder

    private static let tiffTypeSizes: [UInt16: Int] = [
        1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8
    ]

    private static func ifdDataValue(forTag targetTag: UInt16, in data: Data, tiffStart: Int, ifdOffset: Int, endian: TIFFEndian) -> Data? {
        guard let entry = ifdEntry(forTag: targetTag, in: data, tiffStart: tiffStart, ifdOffset: ifdOffset, endian: endian),
              let typeSize = tiffTypeSizes[entry.type] else {
            return nil
        }

        let byteCount = typeSize * entry.count
        guard byteCount > 0 else {
            return nil
        }

        if byteCount <= 4 {
            let range = entry.valueFieldOffset..<(entry.valueFieldOffset + byteCount)
            guard range.upperBound <= data.count else {
                return nil
            }

            return data.subdata(in: range)
        }

        let start = tiffStart + entry.valueOrOffset
        let range = start..<(start + byteCount)
        guard start >= 0, range.upperBound <= data.count else {
            return nil
        }

        return data.subdata(in: range)
    }

    private static func ifdEntryValue(forTag targetTag: UInt16, in data: Data, tiffStart: Int, ifdOffset: Int, endian: TIFFEndian) -> Int? {
        ifdEntry(forTag: targetTag, in: data, tiffStart: tiffStart, ifdOffset: ifdOffset, endian: endian)?.valueOrOffset
    }

    private static func ifdEntry(forTag targetTag: UInt16, in data: Data, tiffStart: Int, ifdOffset: Int, endian: TIFFEndian) -> TIFFRawIFDEntry? {
        guard let absoluteIFDOffset = TIFFReader.offset(base: tiffStart, relative: ifdOffset) else {
            return nil
        }
        return TIFFIFDDecoder.rawEntry(
            forTag: targetTag,
            in: data,
            ifdOffset: absoluteIFDOffset,
            byteOrder: endian
        )
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

        return dictionary.keys.sorted().flatMap { key -> [Candidate] in
            guard let nestedValue = dictionary[key] else { return [] }
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

    private static func readUInt16(_ data: Data, at offset: Int, endian: TIFFEndian) -> UInt16? {
        TIFFReader(data: data, byteOrder: endian).uint16(at: offset)
    }

    private static func readUInt32(_ data: Data, at offset: Int, endian: TIFFEndian) -> UInt32? {
        TIFFReader(data: data, byteOrder: endian).uint32(at: offset)
    }
}

nonisolated enum SonyMakerNoteParser {
    private typealias Endian = TIFFByteOrder

    private typealias IFDEntry = TIFFIFDEntry

    private static let recognizedTags: Set<UInt16> = [
        0x0102, 0x0104, 0x0105, 0x0112, 0x0115, 0x2002, 0x2004, 0x2005,
        0x2006, 0x2008, 0x2009, 0x200a, 0x200b, 0x200e, 0x200f, 0x2011,
        0x2012, 0x2013, 0x2014, 0x2016, 0x2017, 0x201a, 0x201b, 0x201c,
        0x201d, 0x201e, 0x2021, 0x2023, 0x2026, 0x2027, 0x2028, 0x2029,
        0x202b, 0x202c, 0x202d, 0x202e, 0x2031, 0x2032, 0x2033, 0x2034,
        0x2035, 0x2036, 0x2039, 0x204a, 0x205c, 0xb000, 0xb001, 0xb020,
        0xb021, 0xb022, 0xb023, 0xb024, 0xb025, 0xb026, 0xb027, 0xb029,
        0xb02a, 0xb02b, 0xb02c, 0xb040, 0xb041, 0xb042, 0xb043, 0xb044,
        0xb047, 0xb048, 0xb049, 0xb04a, 0xb04b, 0xb04e, 0xb04f, 0xb050,
        0xb052, 0xb054
    ]

    static func parse(_ data: Data) -> [String: String] {
        var bestFields: [String: String] = [:]
        var bestScore = 0

        for offset in candidateIFDOffsets(in: data) {
            for endian in [Endian.little, .big] {
                let entries = parseIFD(in: data, offset: offset, endian: endian)
                guard !entries.isEmpty else {
                    continue
                }

                var fields: [String: String] = [:]
                var recognizedCount = 0

                for entry in entries {
                    if recognizedTags.contains(entry.tag) {
                        recognizedCount += 1
                    }

                    for (title, component) in components(for: entry) {
                        append(component, to: title, in: &fields)
                    }
                }

                let score = recognizedCount * 3 + fields.count
                if score > bestScore {
                    bestScore = score
                    bestFields = fields
                }
            }
        }

        return bestFields
    }

    static func hasSonyHeader(_ data: Data) -> Bool {
        data.starts(with: Data("SONY DSC".utf8)) ||
        data.starts(with: Data("SONY CAM".utf8)) ||
        data.starts(with: Data("SONY MOBILE".utf8)) ||
        data.starts(with: Data([0x00, 0x00]) + Data("SONY PIC".utf8)) ||
        data.starts(with: Data("VHAB     ".utf8))
    }

    static func decodeFallbackValue(for normalizedKey: String, rawValue: Any) -> String {
        switch true {
        case matches(normalizedKey, aliases: ["quality"]):
            return mappedFallbackValue(rawValue, mapping: quality)
        case matches(normalizedKey, aliases: ["rawfiletype"]):
            return mappedFallbackValue(rawValue, mapping: rawFileType)
        case matches(normalizedKey, aliases: ["jpegheifswitch"]):
            return mappedFallbackValue(rawValue, mapping: jpegHEIFSwitch)
        case matches(normalizedKey, aliases: ["whitebalance"]):
            return mappedFallbackValue(rawValue, mapping: whiteBalance)
        case matches(normalizedKey, aliases: ["whitebalancefinetune", "wbshiftabgm", "wbshiftabgmprecise"]):
            return whiteBalanceShiftDescription(integerArray(from: rawValue)) ?? MetadataParser.readableValue(rawValue)
        case matches(normalizedKey, aliases: ["colortemperature", "colortemperaturesetting"]):
            return colorTemperatureDescription(firstInteger(from: rawValue)) ?? MetadataParser.readableValue(rawValue)
        case matches(normalizedKey, aliases: ["colorcompensationfilter", "colorcompensationfilterset"]):
            return colorFilterDescription(firstInteger(from: rawValue)) ?? MetadataParser.readableValue(rawValue)
        case matches(normalizedKey, aliases: ["colormode", "creativestyle"]):
            return mappedFallbackValue(rawValue, mapping: colorMode)
        case matches(normalizedKey, aliases: ["scenemode"]):
            return mappedFallbackValue(rawValue, mapping: sceneMode)
        case matches(normalizedKey, aliases: ["exposuremode"]):
            return mappedFallbackValue(rawValue, mapping: exposureMode)
        case matches(normalizedKey, aliases: ["exposureprogram"]):
            return mappedFallbackValue(rawValue, mapping: exposureProgram)
        case matches(normalizedKey, aliases: ["meteringmode2"]):
            return mappedFallbackValue(rawValue, mapping: meteringMode2)
        case matches(normalizedKey, aliases: ["dynamicrangeoptimizer"]):
            return mappedFallbackValue(rawValue, mapping: dynamicRangeOptimizer)
        case matches(normalizedKey, aliases: ["imagestabilization"]):
            return mappedFallbackValue(rawValue, mapping: offOnNA)
        case matches(normalizedKey, aliases: ["focusmode"]):
            return mappedFallbackValue(rawValue, mapping: focusMode)
        case matches(normalizedKey, aliases: ["afareamode", "afareamodesetting"]):
            return mappedFallbackValue(rawValue, mapping: afAreaMode)
        case matches(normalizedKey, aliases: ["afilluminator"]):
            return mappedFallbackValue(rawValue, mapping: offAutoNA)
        case matches(normalizedKey, aliases: ["afpointselected"]):
            return mappedFallbackValue(rawValue, mapping: afPointSelected)
        case matches(normalizedKey, aliases: ["aftracking"]):
            return mappedFallbackValue(rawValue, mapping: afTracking)
        case matches(normalizedKey, aliases: ["releasemode"]):
            return mappedFallbackValue(rawValue, mapping: releaseMode)
        case matches(normalizedKey, aliases: ["longexposurenoisereduction"]):
            return mappedFallbackValue(rawValue, mapping: longExposureNoiseReduction)
        case matches(normalizedKey, aliases: ["highisonoisereduction"]):
            return mappedFallbackValue(rawValue, mapping: highISONoiseReduction)
        case matches(normalizedKey, aliases: ["pictureeffect"]):
            return mappedFallbackValue(rawValue, mapping: pictureEffect)
        case matches(normalizedKey, aliases: ["softskineffect"]):
            return mappedFallbackValue(rawValue, mapping: softSkinEffect)
        case matches(normalizedKey, aliases: ["autoportraitframed", "electronicfrontcurtainshutter", "vignettingcorrection", "lateralchromaticaberration", "distortioncorrectionsetting"]):
            return mappedFallbackValue(rawValue, mapping: offOnAutoNA)
        default:
            return MetadataParser.readableValue(rawValue)
        }
    }

    private static func candidateIFDOffsets(in data: Data) -> [Int] {
        var offsets: [Int] = []

        if hasSonyHeader(data) {
            offsets.append(12)
        }

        if let tiff = locateTIFFHeader(in: data),
           let ifdOffsetValue = readUInt32(data, at: tiff.start + 4, endian: tiff.endian) {
            offsets.append(tiff.start + Int(ifdOffsetValue))
        }

        offsets.append(0)

        var seenOffsets = Set<Int>()
        return offsets.filter { offset in
            guard offset >= 0, offset + 2 <= data.count else {
                return false
            }

            return seenOffsets.insert(offset).inserted
        }
    }

    private static func parseIFD(in data: Data, offset: Int, endian: Endian) -> [IFDEntry] {
        TIFFIFDDecoder.entries(
            in: data,
            ifdOffset: offset,
            byteOrder: endian,
            valueOffsetBases: [0, offset]
        )
    }

    private static func components(for entry: IFDEntry) -> [(String, String)] {
        let values = numericValues(entry)
        let signedValues = signedNumericValues(entry)
        let rationals = rationalValues(entry)
        let string = asciiString(entry.valueData)

        switch entry.tag {
        case 0x0102:
            return mappedComponent("图像质量", values.first, mapping: quality)
        case 0x0104:
            return rationals.first.map { [("曝光补偿", "闪光: \(formatSignedRational($0)) EV")] } ?? []
        case 0x0105:
            return mappedComponent("增距镜", values.first, mapping: teleconverter)
        case 0x0112:
            return [("白平衡偏移", values.map(String.init).joined(separator: ", "))].filter { !$0.1.isEmpty }
        case 0x0115:
            return mappedComponent("白平衡", values.first, mapping: whiteBalance)
        case 0x2002:
            return valueComponent("评分", values.first)
        case 0x2004:
            return valueComponent("对比度", signedValues.first ?? values.first)
        case 0x2005:
            return valueComponent("饱和度", signedValues.first ?? values.first)
        case 0x2006:
            return valueComponent("锐度", signedValues.first ?? values.first)
        case 0x2008:
            return mappedComponent("长曝光降噪", values.first, mapping: longExposureNoiseReduction)
        case 0x2009:
            return mappedComponent("高 ISO 降噪", values.first, mapping: highISONoiseReduction)
        case 0x200a:
            return [("HDR", hdrDescription(values))]
        case 0x200b:
            return mappedComponent("高 ISO 降噪", values.first, mapping: offOnNA255).map { ($0.0, "多帧降噪: \($0.1)") }
        case 0x200e:
            return mappedComponent("照片效果", values.first, mapping: pictureEffect)
        case 0x200f:
            return mappedComponent("照片效果", values.first, mapping: softSkinEffect).map { ($0.0, "柔肤: \($0.1)") }
        case 0x2011:
            return mappedComponent("镜头校正", values.first, mapping: offAutoNA).map { ($0.0, "暗角: \($0.1)") }
        case 0x2012:
            return mappedComponent("镜头校正", values.first, mapping: offAutoNA).map { ($0.0, "横向色差: \($0.1)") }
        case 0x2013:
            return mappedComponent("镜头校正", values.first, mapping: offAutoNA).map { ($0.0, "畸变: \($0.1)") }
        case 0x2014, 0x2026:
            return [("白平衡偏移", whiteBalanceShiftDescription(signedValues) ?? values.map(String.init).joined(separator: ", "))].filter { !$0.1.isEmpty }
        case 0x2016:
            return mappedComponent("自动人像构图", values.first, mapping: noYes)
        case 0x2017:
            return mappedComponent("闪光灯", values.first, mapping: flashAction)
        case 0x201a:
            return mappedComponent("电子前帘快门", values.first, mapping: offOn)
        case 0x201b, 0xb04e, 0xb042:
            return mappedComponent("对焦模式", values.first, mapping: focusMode)
        case 0x201c, 0xb043:
            return mappedComponent("AF 区域模式", values.first, mapping: afAreaMode)
        case 0x201d:
            return pointComponent("AF 点", values)
        case 0x201e:
            return mappedComponent("AF 点", signedValues.first ?? values.first, mapping: afPointSelected)
        case 0x2021:
            return mappedComponent("AF 跟踪", values.first, mapping: afTracking)
        case 0x2023:
            return mappedComponent("高 ISO 降噪", values.first, mapping: multiFrameNREffect).map { ($0.0, "多帧效果: \($0.1)") }
        case 0x2027, 0x204a:
            return rectangleComponent("AF 点", values)
        case 0x2028:
            return [("镜头校正", variableLowPassFilterDescription(values))].filter { !$0.1.isEmpty }
        case 0x2029:
            return mappedComponent("图像质量", values.first, mapping: rawFileType)
        case 0x202b:
            return mappedComponent("白平衡", values.first, mapping: prioritySetInAWB).map { ($0.0, "AWB 优先: \($0.1)") }
        case 0x202c:
            return mappedComponent("测光模式", values.first, mapping: meteringMode2)
        case 0x202d:
            return rationals.first.map { [("曝光补偿", "标准调整: \(formatSignedRational($0)) EV")] } ?? []
        case 0x202e:
            return [("图像质量", qualityPairDescription(values) ?? values.map(String.init).joined(separator: " "))].filter { !$0.1.isEmpty }
        case 0x2031:
            return string.map { [("序列号", $0)] } ?? []
        case 0x2032:
            return valueComponent("阴影", signedValues.first ?? values.first)
        case 0x2033:
            return valueComponent("高光", signedValues.first ?? values.first)
        case 0x2034:
            return valueComponent("淡化", signedValues.first ?? values.first)
        case 0x2035:
            return valueComponent("锐度", signedValues.first ?? values.first).map { ($0.0, "范围: \($0.1)") }
        case 0x2036:
            return valueComponent("清晰度", signedValues.first ?? values.first)
        case 0x2039:
            return mappedComponent("JPEG/HEIF", values.first, mapping: jpegHEIFSwitch)
        case 0x205c:
            return mappedComponent("裁切模式", values.first, mapping: stepCropShooting)
        case 0xb000:
            return [("文件格式", fileFormatDescription(values))]
        case 0xb001:
            return [("SONY 型号 ID", sonyModelID[values.first ?? -1] ?? values.first.map(String.init) ?? "")].filter { !$0.1.isEmpty }
        case 0xb020:
            return string.map { [("创意风格", creativeStyle[$0] ?? $0)] } ?? []
        case 0xb021:
            return [("色温", colorTemperatureDescription(values.first) ?? "")].filter { !$0.1.isEmpty }
        case 0xb022:
            return [("色彩补偿滤镜", colorFilterDescription(signedValues.first ?? values.first) ?? "")].filter { !$0.1.isEmpty }
        case 0xb023:
            return mappedComponent("场景模式", values.first, mapping: sceneMode)
        case 0xb024:
            return mappedComponent("曝光模式", values.first, mapping: zoneMatching).map { ($0.0, "区域匹配: \($0.1)") }
        case 0xb025, 0xb04f:
            return mappedComponent("动态范围优化", values.first, mapping: dynamicRangeOptimizer)
        case 0xb026:
            return mappedComponent("防抖", values.first, mapping: offOnNA)
        case 0xb027:
            return [("镜头类型", lensTypeDescription(values.first))]
        case 0xb029:
            return mappedComponent("创意风格", values.first, mapping: colorMode)
        case 0xb02a:
            return [("镜头规格", lensSpecDescription(values))]
        case 0xb02b:
            return sizeComponent("图像尺寸", label: "完整", values: values)
        case 0xb02c:
            return sizeComponent("图像尺寸", label: "预览", values: values)
        case 0xb040:
            return mappedComponent("微距", values.first, mapping: macro)
        case 0xb041:
            return mappedComponent("曝光模式", values.first, mapping: exposureMode)
        case 0xb044:
            return mappedComponent("AF 辅助灯", values.first, mapping: offAutoNA)
        case 0xb047:
            return mappedComponent("图像质量", values.first, mapping: jpegQuality)
        case 0xb048:
            return [("曝光补偿", flashLevelDescription(signedValues.first ?? values.first) ?? "")].filter { !$0.1.isEmpty }
        case 0xb049:
            return mappedComponent("释放模式", values.first, mapping: releaseMode)
        case 0xb04a:
            return [("连拍", sequenceNumberDescription(values.first) ?? "")].filter { !$0.1.isEmpty }
        case 0xb04b:
            return mappedComponent("防抖", values.first, mapping: antiBlur)
        case 0xb050:
            return mappedComponent("高 ISO 降噪", values.first, mapping: highISONoiseReduction2)
        case 0xb052:
            return mappedComponent("场景模式", values.first, mapping: intelligentAuto)
        case 0xb054:
            return mappedComponent("白平衡", values.first, mapping: whiteBalance2)
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

    private static func mappedComponent(_ title: String, _ value: Int?, mapping: [Int: String]) -> [(String, String)] {
        guard let value else {
            return []
        }

        return [(title, mapping[value] ?? String(value))]
    }

    private static func valueComponent(_ title: String, _ value: Int?) -> [(String, String)] {
        guard let value else {
            return []
        }

        return [(title, String(value))]
    }

    private static func pointComponent(_ title: String, _ values: [Int]) -> [(String, String)] {
        guard values.count >= 2 else {
            return []
        }

        return [(title, "X \(values[0]), Y \(values[1])")]
    }

    private static func rectangleComponent(_ title: String, _ values: [Int]) -> [(String, String)] {
        guard values.count >= 4 else {
            return pointComponent(title, values)
        }

        return [(title, "X \(values[0]), Y \(values[1]), W \(values[2]), H \(values[3])")]
    }

    private static func sizeComponent(_ title: String, label: String, values: [Int]) -> [(String, String)] {
        guard values.count >= 2 else {
            return []
        }

        return [(title, "\(label): \(values[0]) x \(values[1])")]
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
        case 6:
            return entry.valueData.prefix(entry.count).map { Int(Int8(bitPattern: $0)) }
        case 8:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 2), by: 2).compactMap {
                readInt16(entry.valueData, at: $0, endian: entry.endian).map(Int.init)
            }
        case 9:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 4), by: 4).compactMap {
                readInt32(entry.valueData, at: $0, endian: entry.endian).map(Int.init)
            }
        default:
            return []
        }
    }

    private static func signedNumericValues(_ entry: IFDEntry) -> [Int] {
        switch entry.type {
        case 6:
            return entry.valueData.prefix(entry.count).map { Int(Int8(bitPattern: $0)) }
        case 8, 3:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 2), by: 2).compactMap {
                readInt16(entry.valueData, at: $0, endian: entry.endian).map(Int.init)
            }
        case 9:
            return stride(from: 0, to: min(entry.valueData.count, entry.count * 4), by: 4).compactMap {
                readInt32(entry.valueData, at: $0, endian: entry.endian).map(Int.init)
            }
        default:
            return []
        }
    }

    private static func rationalValues(_ entry: IFDEntry) -> [Double] {
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

    private static func asciiString(_ data: Data) -> String? {
        let bytes = data.prefix { $0 != 0 }
        guard !bytes.isEmpty else {
            return nil
        }

        return String(data: Data(bytes), encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func mappedFallbackValue(_ rawValue: Any, mapping: [Int: String]) -> String {
        guard let value = firstInteger(from: rawValue) else {
            return MetadataParser.readableValue(rawValue)
        }

        return mapping[value] ?? String(value)
    }

    private static func matches(_ normalizedKey: String, aliases: [String]) -> Bool {
        aliases.contains { alias in
            let normalizedAlias = alias
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")

            return normalizedKey == normalizedAlias || normalizedKey.contains(normalizedAlias) || normalizedKey.hasSuffix(normalizedAlias)
        }
    }

    private static func formatSigned(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }

    private static func formatSignedRational(_ value: Double) -> String {
        if value == 0 {
            return "0"
        }

        if value.rounded() == value {
            return value > 0 ? "+\(Int(value))" : String(Int(value))
        }

        return value > 0 ? String(format: "+%.2f", value) : String(format: "%.2f", value)
    }

    private static func colorTemperatureDescription(_ value: Int?) -> String? {
        guard let value else {
            return nil
        }

        if value == 0 {
            return "Auto"
        }

        if value == -1 || value == Int(UInt32.max) {
            return "n/a"
        }

        return "\(value) K"
    }

    private static func colorFilterDescription(_ value: Int?) -> String? {
        guard let value else {
            return nil
        }

        if value == 0 {
            return "0"
        }

        return value > 0 ? "M\(value) (\(formatSigned(value)))" : "G\(abs(value)) (\(value))"
    }

    private static func whiteBalanceShiftDescription(_ values: [Int]?) -> String? {
        guard let values, values.count >= 2 else {
            return nil
        }

        return "A/B \(formatSigned(values[0])), G/M \(formatSigned(values[1]))"
    }

    private static func hdrDescription(_ values: [Int]) -> String {
        guard !values.isEmpty else {
            return ""
        }

        let hdr = hdrMode[values[0]] ?? String(values[0])
        guard values.count > 1 else {
            return hdr
        }

        let status = hdrStatus[values[1]] ?? String(values[1])
        return "\(hdr), \(status)"
    }

    private static func fileFormatDescription(_ values: [Int]) -> String {
        let key = values.prefix(4).map(String.init).joined(separator: " ")
        return fileFormat[key] ?? (key.isEmpty ? "" : key)
    }

    private static func qualityPairDescription(_ values: [Int]) -> String? {
        guard values.count >= 2 else {
            return nil
        }

        return qualityPair["\(values[0]) \(values[1])"]
    }

    private static func sequenceNumberDescription(_ value: Int?) -> String? {
        guard let value else {
            return nil
        }

        switch value {
        case 0:
            return "Single"
        case 65535:
            return "n/a"
        default:
            return String(value)
        }
    }

    private static func flashLevelDescription(_ value: Int?) -> String? {
        guard let value else {
            return nil
        }

        switch value {
        case -32768:
            return "闪光级别: Low"
        case 32767:
            return "闪光级别: High"
        case 128:
            return "闪光级别: n/a"
        case 0:
            return "闪光级别: Normal"
        case -9...9:
            return "闪光级别: \(formatSignedRational(Double(value) / 3.0)) EV"
        default:
            return "闪光级别: \(value)"
        }
    }

    private static func variableLowPassFilterDescription(_ values: [Int]) -> String {
        guard values.count >= 2 else {
            return ""
        }

        return variableLowPassFilter["\(values[0]) \(values[1])"] ?? values.prefix(2).map(String.init).joined(separator: " ")
    }

    private static func lensTypeDescription(_ value: Int?) -> String {
        guard let value else {
            return ""
        }

        return lensType[value] ?? String(value)
    }

    private static func lensSpecDescription(_ values: [Int]) -> String {
        guard values.count >= 8 else {
            return values.map(String.init).joined(separator: " ")
        }

        let minFocal = values[0]
        let maxFocal = values[1]
        let minAperture = Double(values[2]) / 10.0
        let maxAperture = Double(values[3]) / 10.0
        let focal = minFocal == maxFocal ? "\(minFocal)mm" : "\(minFocal)-\(maxFocal)mm"
        let aperture = abs(minAperture - maxAperture) < 0.01 ? "f/\(formatCompact(minAperture))" : "f/\(formatCompact(minAperture))-\(formatCompact(maxAperture))"

        var features: [String] = []
        let flags = values[4]
        if flags & 0x01 != 0 { features.append("DT") }
        if flags & 0x02 != 0 { features.append("E") }
        if flags & 0x04 != 0 { features.append("ZA") }
        if flags & 0x08 != 0 { features.append("G") }
        if flags & 0x10 != 0 { features.append("SSM") }
        if flags & 0x20 != 0 { features.append("SAM") }
        if flags & 0x40 != 0 { features.append("OSS") }
        if flags & 0x80 != 0 { features.append("STF") }

        let featureText = features.isEmpty ? "" : " \(features.joined(separator: " "))"
        return "\(focal) \(aperture)\(featureText)"
    }

    private static func formatCompact(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.1f", value)
    }

    private static let noYes = [0: "No", 1: "Yes"]
    private static let offOn = [0: "Off", 1: "On"]
    private static let offOnNA = [0: "Off", 1: "On", Int(UInt32.max): "n/a"]
    private static let offOnNA255 = [0: "Off", 1: "On", 255: "n/a"]
    private static let offAutoNA = [0: "Off", 1: "Auto", 65535: "n/a", Int(UInt32.max): "n/a"]
    private static let offOnAutoNA = [0: "Off", 1: "On", 2: "Auto", 65535: "n/a", Int(UInt32.max): "n/a"]

    private static let quality = [
        0: "RAW", 1: "Super Fine", 2: "Fine", 3: "Standard", 4: "Economy",
        5: "Extra Fine", 6: "RAW + JPEG/HEIF", 7: "Compressed RAW",
        8: "Compressed RAW + JPEG", 9: "Light", Int(UInt32.max): "n/a"
    ]

    private static let jpegQuality = [0: "Standard", 1: "Fine", 2: "Extra Fine", 65535: "n/a"]
    private static let jpegHEIFSwitch = [0: "JPEG", 1: "HEIF", 65535: "n/a"]
    private static let rawFileType = [0: "Compressed RAW", 1: "Uncompressed RAW", 2: "Lossless Compressed RAW", 3: "Compressed RAW 2", 65535: "n/a"]

    private static let qualityPair = [
        "0 0": "n/a", "0 1": "Standard", "0 2": "Fine", "0 3": "Extra Fine", "0 4": "Light",
        "1 0": "RAW", "1 1": "RAW + Standard", "1 2": "RAW + Fine", "1 3": "RAW + Extra Fine", "1 4": "RAW + Light",
        "2 0": "S-size RAW", "2 1": "S-size RAW + Standard", "2 2": "S-size RAW + Fine", "2 3": "S-size RAW + Extra Fine", "2 4": "S-size RAW + Light",
        "3 0": "M-size RAW", "3 1": "M-size RAW + Standard", "3 2": "M-size RAW + Fine", "3 3": "M-size RAW + Extra Fine", "3 4": "M-size RAW + Light",
        "4 0": "Compressed RAW", "4 1": "Compressed RAW + Standard", "4 2": "Compressed RAW + Fine", "4 3": "Compressed RAW + Extra Fine", "4 4": "Compressed RAW + Light",
        "5 0": "Compressed (HQ) RAW", "5 1": "Compressed (HQ) RAW + Standard", "5 2": "Compressed (HQ) RAW + Fine", "5 3": "Compressed (HQ) RAW + Extra Fine", "5 4": "Compressed (HQ) RAW + Light"
    ]

    private static let whiteBalance = [
        0x0: "Auto", 0x1: "Color Temperature/Color Filter", 0x10: "Daylight",
        0x20: "Cloudy", 0x30: "Shade", 0x40: "Tungsten", 0x50: "Flash",
        0x60: "Fluorescent", 0x70: "Custom", 0x80: "Underwater"
    ]

    private static let whiteBalance2 = [
        0: "Auto", 4: "Custom", 5: "Daylight", 6: "Cloudy",
        7: "Cool White Fluorescent", 8: "Day White Fluorescent",
        9: "Daylight Fluorescent", 10: "Incandescent2",
        11: "Warm White Fluorescent", 14: "Incandescent",
        15: "Flash", 17: "Underwater 1 (Blue Water)",
        18: "Underwater 2 (Green Water)", 19: "Underwater Auto"
    ]

    private static let prioritySetInAWB = [0: "Standard", 1: "Ambience", 2: "White"]

    private static let creativeStyle = [
        "AdobeRGB": "Adobe RGB", "Autumnleaves": "Autumn Leaves", "BW": "B&W",
        "Clear": "Clear", "Deep": "Deep", "FL": "FL", "IN": "IN",
        "Landscape": "Landscape", "Light": "Light", "Neutral": "Neutral",
        "Nightview": "Night View/Portrait", "None": "None", "Portrait": "Portrait",
        "Real": "Real", "SH": "SH", "Sepia": "Sepia", "Standard": "Standard",
        "Sunset": "Sunset", "VV2": "Vivid 2", "Vivid": "Vivid"
    ]

    private static let colorMode = [
        0: "Standard", 1: "Vivid", 2: "Portrait", 3: "Landscape", 4: "Sunset",
        5: "Night View/Portrait", 6: "B&W", 7: "Adobe RGB", 12: "Neutral",
        13: "Clear", 14: "Deep", 15: "Light", 16: "Autumn Leaves", 17: "Sepia",
        18: "FL", 19: "Vivid 2", 20: "IN", 21: "SH", 22: "FL2", 23: "FL3",
        100: "Neutral", 101: "Clear", 102: "Deep", 103: "Light",
        104: "Night View", 105: "Autumn Leaves", 255: "Off", Int(UInt32.max): "n/a"
    ]

    private static let sceneMode = [
        0: "Standard", 1: "Portrait", 2: "Text", 3: "Night Scene", 4: "Sunset",
        5: "Sports", 6: "Landscape", 7: "Night Portrait", 8: "Macro",
        9: "Super Macro", 16: "Auto", 17: "Night View/Portrait",
        18: "Sweep Panorama", 19: "Handheld Night Shot", 20: "Anti Motion Blur",
        21: "Cont. Priority AE", 22: "Auto+", 23: "3D Sweep Panorama",
        24: "Superior Auto", 25: "High Sensitivity", 26: "Fireworks",
        27: "Food", 28: "Pet", 33: "HDR", 65535: "n/a"
    ]

    private static let exposureMode = [
        0: "Program AE", 1: "Portrait", 2: "Beach", 3: "Sports", 4: "Snow",
        5: "Landscape", 6: "Auto", 7: "Aperture-priority AE",
        8: "Shutter speed priority AE", 9: "Night Scene / Twilight",
        10: "Hi-Speed Shutter", 11: "Twilight Portrait", 12: "Soft Snap/Portrait",
        13: "Fireworks", 14: "Smile Shutter", 15: "Manual", 18: "High Sensitivity",
        19: "Macro", 20: "Advanced Sports Shooting", 29: "Underwater",
        33: "Food", 34: "Sweep Panorama", 35: "Handheld Night Shot",
        36: "Anti Motion Blur", 37: "Pet", 38: "Backlight Correction HDR",
        39: "Superior Auto", 40: "Background Defocus", 41: "Soft Skin",
        42: "3D Image", 65535: "n/a"
    ]

    private static let exposureProgram = [
        0: "Program AE", 1: "Aperture-priority AE", 2: "Shutter speed priority AE",
        3: "Manual", 4: "Auto", 5: "iAuto", 6: "Superior Auto", 7: "iAuto+",
        8: "Portrait", 9: "Landscape", 10: "Twilight", 11: "Twilight Portrait",
        12: "Sunset", 14: "Action (High speed)"
    ]

    private static let meteringMode2 = [
        0x100: "Multi-segment", 0x200: "Center-weighted average",
        0x301: "Spot (Standard)", 0x302: "Spot (Large)",
        0x400: "Average", 0x500: "Highlight"
    ]

    private static let dynamicRangeOptimizer = [
        0: "Off", 1: "Standard", 2: "Advanced Auto", 3: "Auto",
        8: "Advanced Lv1", 9: "Advanced Lv2", 10: "Advanced Lv3",
        11: "Advanced Lv4", 12: "Advanced Lv5", 16: "Lv1", 17: "Lv2",
        18: "Lv3", 19: "Lv4", 20: "Lv5"
    ]

    private static let focusMode = [0: "Manual", 1: "AF-S", 2: "AF-C", 3: "AF-C", 4: "AF-A", 5: "Semi-manual", 6: "DMF", 7: "AF-D", 65535: "n/a"]
    private static let afAreaMode = [0: "Wide", 1: "Multi", 2: "Center", 3: "Flexible Spot", 4: "Flexible Spot", 6: "Touch", 8: "Zone", 9: "Spot", 11: "Zone", 12: "Expanded Flexible Spot", 13: "Custom AF Area", 14: "Tracking", 15: "Face Tracking", 255: "Manual", 65535: "n/a"]
    private static let afPointSelected = [-1: "Auto", 0: "Auto", 1: "Center", 2: "Top", 3: "Upper-right", 4: "Right", 5: "Lower-right", 6: "Bottom", 7: "Lower-left", 8: "Left", 9: "Upper-left", 10: "Far Right", 11: "Far Left", 12: "Upper-middle", 13: "Near Right", 14: "Lower-middle", 15: "Near Left", 16: "Upper Far Right", 17: "Lower Far Right", 18: "Lower Far Left", 19: "Upper Far Left"]
    private static let afTracking = [0: "Off", 1: "Face tracking", 2: "Lock On AF"]

    private static let flashAction = [0: "Did not fire", 1: "Flash Fired", 2: "External Flash Fired", 3: "Wireless Controlled Flash Fired"]
    private static let releaseMode = [0: "Normal", 2: "Continuous", 5: "Exposure Bracketing", 6: "White Balance Bracketing", 8: "DRO Bracketing", 65535: "n/a"]

    private static let longExposureNoiseReduction = [0x0: "Off", 0x1: "On (unused)", 0x10001: "On (dark subtracted)", Int(UInt32.max): "n/a"]
    private static let highISONoiseReduction = [0: "Off", 1: "Low", 2: "Normal", 3: "High", 256: "Auto", 65535: "n/a"]
    private static let highISONoiseReduction2 = [0: "Normal", 1: "High", 2: "Low", 3: "Off", 65535: "n/a"]
    private static let multiFrameNREffect = [0: "Normal", 1: "High"]

    private static let hdrMode = [0x0: "Off", 0x1: "Auto", 0x10: "1.0 EV", 0x11: "1.5 EV", 0x12: "2.0 EV", 0x13: "2.5 EV", 0x14: "3.0 EV", 0x15: "3.5 EV", 0x16: "4.0 EV", 0x17: "4.5 EV", 0x18: "5.0 EV", 0x19: "5.5 EV", 0x1a: "6.0 EV"]
    private static let hdrStatus = [0: "Uncorrected image", 1: "HDR image (good)", 2: "HDR image (fail 1)", 3: "HDR image (fail 2)"]

    private static let pictureEffect = [
        0: "Off", 1: "Toy Camera", 2: "Pop Color", 3: "Posterization",
        4: "Posterization B/W", 5: "Retro Photo", 6: "Soft High Key",
        7: "Partial Color (red)", 8: "Partial Color (green)",
        9: "Partial Color (blue)", 10: "Partial Color (yellow)",
        13: "High Contrast Monochrome", 16: "Toy Camera (normal)",
        17: "Toy Camera (cool)", 18: "Toy Camera (warm)", 19: "Toy Camera (green)",
        20: "Toy Camera (magenta)", 32: "Soft Focus (low)", 33: "Soft Focus",
        34: "Soft Focus (high)", 48: "Miniature (auto)", 49: "Miniature (top)",
        50: "Miniature (middle horizontal)", 51: "Miniature (bottom)",
        52: "Miniature (left)", 53: "Miniature (middle vertical)",
        54: "Miniature (right)", 64: "HDR Painting (low)", 65: "HDR Painting",
        66: "HDR Painting (high)", 80: "Rich-tone Monochrome",
        97: "Water Color", 98: "Water Color 2", 112: "Illustration (low)",
        113: "Illustration", 114: "Illustration (high)"
    ]

    private static let softSkinEffect = [0: "Off", 1: "Low", 2: "Mid", 3: "High", Int(UInt32.max): "n/a"]
    private static let zoneMatching = [0: "ISO Setting Used", 1: "High Key", 2: "Low Key"]
    private static let macro = [0: "Off", 1: "On", 2: "Close Focus", 65535: "n/a"]
    private static let antiBlur = [0: "Off", 1: "On (Continuous)", 2: "On (Shooting)", 65535: "n/a"]
    private static let intelligentAuto = [0: "Off", 1: "On", 2: "Advanced"]
    private static let stepCropShooting = [0: "35mm (Off)", 1: "50mm", 2: "70mm"]
    private static let variableLowPassFilter = ["0 0": "n/a", "1 0": "Off", "1 1": "Standard", "1 2": "High", "65535 65535": "n/a"]

    private static let teleconverter = [
        0x0: "None", 0x4: "Minolta/Sony AF 1.4x APO (D)",
        0x5: "Minolta/Sony AF 2x APO (D)", 0x48: "Minolta/Sony AF 2x APO (D)",
        0x50: "Minolta AF 2x APO II", 0x60: "Minolta AF 2x APO",
        0x88: "Minolta/Sony AF 1.4x APO (D)", 0x90: "Minolta AF 1.4x APO II",
        0xa0: "Minolta AF 1.4x APO"
    ]

    private static let fileFormat = [
        "0 0 0 2": "JPEG", "1 0 0 0": "SR2", "2 0 0 0": "ARW 1.0",
        "3 0 0 0": "ARW 2.0", "3 1 0 0": "ARW 2.1", "3 2 0 0": "ARW 2.2",
        "3 3 0 0": "ARW 2.3", "3 3 1 0": "ARW 2.3.1",
        "3 3 2 0": "ARW 2.3.2", "3 3 3 0": "ARW 2.3.3",
        "3 3 5 0": "ARW 2.3.5", "4 0 0 0": "ARW 4.0",
        "4 0 1 0": "ARW 4.0.1", "5 0 0 0": "ARW 5.0",
        "5 0 1 0": "ARW 5.0.1", "6 0 0 0": "ARW 6.0"
    ]

    private static let sonyModelID = [
        2: "DSC-R1", 256: "DSLR-A100", 257: "DSLR-A900", 258: "DSLR-A700",
        259: "DSLR-A200", 260: "DSLR-A350", 261: "DSLR-A300",
        269: "DSLR-A850", 278: "NEX-5", 279: "NEX-3", 280: "SLT-A33",
        281: "SLT-A55 / SLT-A55V", 286: "SLT-A65 / SLT-A65V",
        287: "SLT-A77 / SLT-A77V", 289: "NEX-7", 294: "SLT-A99 / SLT-A99V",
        297: "DSC-RX100", 298: "DSC-RX1", 306: "ILCE-7", 311: "ILCE-7R",
        312: "ILCE-6000", 317: "DSC-RX100M3", 318: "ILCE-7S",
        319: "ILCA-77M2", 340: "ILCE-7M2", 347: "ILCE-7RM2",
        350: "ILCE-7SM2", 354: "ILCA-99M2", 358: "ILCE-9",
        362: "ILCE-7RM3", 363: "ILCE-7M3", 371: "ILCE-6400",
        374: "DSC-RX100M7", 375: "ILCE-7RM4", 376: "ILCE-9M2",
        381: "ILCE-7C", 383: "ILCE-7SM3", 384: "ILCE-1",
        388: "ILCE-7M4", 390: "ILCE-7RM5", 392: "ILCE-9M3",
        394: "ILCE-6700", 396: "ILCE-7CR", 397: "ILCE-7CM2",
        400: "ILCE-1M2", 407: "ILCE-7M5"
    ]

    private static let lensType = [
        0: "Minolta AF 28-85mm F3.5-4.5 New",
        1: "Minolta AF 80-200mm F2.8 HS-APO G",
        2: "Minolta AF 28-70mm F2.8 G",
        4: "Minolta AF 85mm F1.4G",
        20: "Minolta/Sony 135mm F2.8 [T4.5] STF",
        24: "Minolta/Sony AF 24-105mm F3.5-4.5 (D)",
        25: "Minolta AF 100-300mm F4.5-5.6 APO (D)",
        27: "Minolta/Sony AF 75-300mm F4.5-5.6 (D)",
        28: "Minolta/Sony AF 50mm F2.8 Macro (D)",
        29: "Minolta/Sony AF 100mm F2.8 Macro (D)",
        30: "Minolta/Sony AF 20mm F2.8",
        31: "Minolta/Sony AF 50mm F1.4",
        32: "Minolta/Sony AF 300mm F2.8 G",
        35: "Minolta AF 35mm F1.4 G",
        38: "Minolta AF 17-35mm F2.8-4 (D)",
        39: "Minolta AF 28-75mm F2.8 (D)",
        45: "Sony FE 24-70mm F4 ZA OSS",
        46: "Sony FE 35mm F2.8 ZA",
        47: "Sony FE 55mm F1.8 ZA",
        48: "Sony FE 28-70mm F3.5-5.6 OSS",
        49: "Sony FE 70-200mm F4 G OSS",
        50: "Sony FE 16-35mm F4 ZA OSS",
        51: "Sony FE 24-240mm F3.5-6.3 OSS",
        52: "Sony FE 28mm F2",
        53: "Sony FE 90mm F2.8 Macro G OSS",
        54: "Sony FE 35mm F1.4 ZA",
        55: "Sony FE 24-70mm F2.8 GM",
        56: "Sony FE 85mm F1.4 GM",
        57: "Sony FE 70-200mm F2.8 GM OSS",
        58: "Sony FE 50mm F1.8",
        59: "Sony FE 100mm F2.8 STF GM OSS",
        60: "Sony FE 100-400mm F4.5-5.6 GM OSS",
        61: "Sony FE 12-24mm F4 G",
        62: "Sony FE 16-35mm F2.8 GM",
        63: "Sony FE 24-105mm F4 G OSS",
        64: "Sony FE 400mm F2.8 GM OSS",
        65: "Sony FE 135mm F1.8 GM",
        66: "Sony FE 200-600mm F5.6-6.3 G OSS",
        67: "Sony FE 600mm F4 GM OSS",
        68: "Sony FE 35mm F1.8",
        69: "Sony FE 20mm F1.8 G",
        70: "Sony FE 12-24mm F2.8 GM",
        71: "Sony FE 50mm F1.2 GM",
        72: "Sony FE 14mm F1.8 GM",
        73: "Sony FE 70-200mm F2.8 GM OSS II",
        74: "Sony FE 24-70mm F2.8 GM II",
        75: "Sony FE 300mm F2.8 GM OSS",
        76: "Sony FE 16-35mm F2.8 GM II",
        32784: "E 16mm F2.8", 32785: "E 18-55mm F3.5-5.6 OSS",
        32786: "E 55-210mm F4.5-6.3 OSS", 32787: "E 18-200mm F3.5-6.3 OSS",
        32788: "E 30mm F3.5 Macro", 32789: "E 24mm F1.8 ZA",
        32790: "E 50mm F1.8 OSS", 32791: "E 16-70mm F4 ZA OSS",
        32792: "E 10-18mm F4 OSS", 32793: "E PZ 16-50mm F3.5-5.6 OSS",
        32794: "E PZ 18-105mm F4 G OSS", 32795: "E 35mm F1.8 OSS",
        32796: "E 20mm F2.8", 32797: "E 18-200mm F3.5-6.3 OSS LE",
        32798: "E 18-135mm F3.5-5.6 OSS", 32800: "E 70-350mm F4.5-6.3 G OSS"
    ]
}
