//
//  MetadataParsing.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import CoreLocation
import Foundation
import ImageIO

enum MetadataParser {
    static func parse(data: Data, fallbackLocation: CLLocation?) -> PhotoMetadata {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else {
            return PhotoMetadata(sections: [], coordinate: fallbackLocation?.coordinate)
        }

        let coordinate = parseCoordinate(from: properties) ?? fallbackLocation?.coordinate
        var sections = properties.compactMap { key, value -> MetadataSection? in
            guard let dictionary = value as? [String: Any] else {
                return nil
            }

            let sectionTitle = readableSectionName(key)
            let items = dictionary
                .map { itemKey, itemValue in
                    MetadataItem(
                        id: "\(key)-\(itemKey)",
                        key: readableItemName(itemKey),
                        value: readableValue(itemValue)
                    )
                }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }

            return items.isEmpty ? nil : MetadataSection(id: key, title: sectionTitle, items: items)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        sections.append(contentsOf: CameraMetadataSectionBuilder.sections(from: properties))
        sections.append(contentsOf: WhiteBalanceMetadataFallbackBuilder.sections(from: properties, existingSections: sections))
        sections.append(contentsOf: WhiteBalanceDebugSectionBuilder.sections(from: properties))

        return PhotoMetadata(sections: sections, coordinate: coordinate)
    }

    private static func parseCoordinate(from properties: [String: Any]) -> CLLocationCoordinate2D? {
        guard let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let latitude = decimalCoordinate(value: gps[kCGImagePropertyGPSLatitude as String], reference: gps[kCGImagePropertyGPSLatitudeRef as String]),
              let longitude = decimalCoordinate(value: gps[kCGImagePropertyGPSLongitude as String], reference: gps[kCGImagePropertyGPSLongitudeRef as String]) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func decimalCoordinate(value: Any?, reference: Any?) -> Double? {
        guard var coordinate = value as? Double else {
            return nil
        }

        if let ref = reference as? String, ref == "S" || ref == "W" {
            coordinate *= -1
        }

        return coordinate
    }

    private static func readableSectionName(_ key: String) -> String {
        switch key {
        case String(kCGImagePropertyExifDictionary):
            return "Exif"
        case String(kCGImagePropertyTIFFDictionary):
            return "TIFF"
        case String(kCGImagePropertyGPSDictionary):
            return "GPS"
        case String(kCGImagePropertyIPTCDictionary):
            return "IPTC"
        case String(kCGImagePropertyPNGDictionary):
            return "PNG"
        case String(kCGImagePropertyJFIFDictionary):
            return "JFIF"
        case String(kCGImagePropertyMakerFujiDictionary):
            return "Fujifilm MakerNote"
        default:
            return key.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        }
    }

    private static func readableItemName(_ key: String) -> String {
        key
            .replacingOccurrences(of: "{GPS}", with: "")
            .replacingOccurrences(of: "{Exif}", with: "")
            .replacingOccurrences(of: "{TIFF}", with: "")
            .replacingOccurrences(of: "{IPTC}", with: "")
            .replacingOccurrences(of: "{PNG}", with: "")
            .replacingOccurrences(of: "{JFIF}", with: "")
            .replacingOccurrences(of: "{MakerFuji}", with: "")
    }

    nonisolated static func readableValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            return array.map { readableValue($0) }.joined(separator: ", ")
        case let dictionary as [String: Any]:
            return dictionary
                .map { "\($0.key): \(readableValue($0.value))" }
                .sorted()
                .joined(separator: "\n")
        default:
            return String(describing: value)
        }
    }
}

enum WhiteBalanceMetadataFallbackBuilder {
    private struct Candidate {
        let key: String
        let value: Any
    }

    private static let targetAliases: [(title: String, aliases: [String])] = [
        ("白平衡", ["whitebalance", "whitebalancemode"]),
        ("白平衡微调", ["whitebalancefinetune", "wbrblevels", "wbrb", "whitebalancerblevels"]),
        ("白平衡偏移", ["whitebalanceshift", "wbshift", "wbgrblevels"])
    ]

    static func sections(from properties: [String: Any], existingSections: [MetadataSection]) -> [MetadataSection] {
        let existingKeys = Set(existingSections.flatMap(\.items).map(\.key))
        let candidates = flatten(properties)
        var items: [MetadataItem] = []
        var usedTitles = Set<String>()

        for field in targetAliases {
            guard !existingKeys.contains(field.title), !usedTitles.contains(field.title) else {
                continue
            }

            guard let candidate = firstCandidate(for: field.aliases, in: candidates) else {
                continue
            }

            let value = formattedValue(for: normalized(candidate.key), rawValue: candidate.value)
            guard !value.isEmpty else {
                continue
            }

            items.append(MetadataItem(id: "white-balance-\(field.title)", key: field.title, value: value))
            usedTitles.insert(field.title)
        }

        guard !items.isEmpty else {
            return []
        }

        return [MetadataSection(id: "white-balance-fallback", title: "白平衡", items: items)]
    }

    private static func firstCandidate(for aliases: [String], in candidates: [Candidate]) -> Candidate? {
        for alias in aliases {
            let needle = normalized(alias)

            if let exact = candidates.first(where: { normalized($0.key) == needle }) {
                return exact
            }

            if let partial = candidates.first(where: { normalized($0.key).contains(needle) }) {
                return partial
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
                .replacingOccurrences(of: "{MakerFuji}", with: "")
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

    private static func formattedValue(for normalizedKey: String, rawValue: Any) -> String {
        if normalizedKey.contains("whitebalance"), let mapped = MetadataKeyTranslator.chineseName(for: normalizedKey), mapped == "白平衡" {
            return MetadataParser.readableValue(rawValue)
        }

        if normalizedKey.contains("finetune") || normalizedKey.contains("shift") || normalizedKey.contains("wbrb") {
            if let values = integerArray(from: rawValue), !values.isEmpty {
                if values.count >= 4 {
                    return "G1 \(signed(values[0])), R \(signed(values[1])), B \(signed(values[2])), G2 \(signed(values[3]))"
                }

                if values.count >= 2 {
                    return "R \(signed(values[0])), B \(signed(values[1]))"
                }

                return "R \(signed(values[0]))"
            }
        }

        return MetadataParser.readableValue(rawValue)
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
            let values = array.compactMap { value -> Int? in
                switch value {
                case let number as NSNumber:
                    return number.intValue
                case let int as Int:
                    return int
                default:
                    return nil
                }
            }
            return values.isEmpty ? nil : values
        default:
            return nil
        }
    }

    private static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }
}

enum WhiteBalanceDebugSectionBuilder {
    private struct Candidate {
        let key: String
        let value: Any
    }

    static func sections(from properties: [String: Any]) -> [MetadataSection] {
        let items = flatten(properties)
            .filter { candidate in
                let key = normalized(candidate.key)
                return key.contains("whitebalance") || key.contains("wb")
            }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { candidate in
                MetadataItem(
                    id: "wb-debug-\(candidate.key)",
                    key: candidate.key,
                    value: formattedValue(candidate.value)
                )
            }

        guard !items.isEmpty else {
            return []
        }

        return [MetadataSection(id: "white-balance-debug", title: "白平衡调试", items: items)]
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
                .replacingOccurrences(of: "{MakerFuji}", with: "")
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

    private static func formattedValue(_ value: Any) -> String {
        if let array = integerArray(from: value), !array.isEmpty {
            return array.map { signed($0) }.joined(separator: ", ")
        }

        return MetadataParser.readableValue(value)
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
            let values = array.compactMap { value -> Int? in
                switch value {
                case let number as NSNumber:
                    return number.intValue
                case let int as Int:
                    return int
                default:
                    return nil
                }
            }
            return values.isEmpty ? nil : values
        default:
            return nil
        }
    }

    private static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }
}

enum MetadataKeyTranslator {
    private static let names: [String: String] = [
        "aperturevalue": "光圈值",
        "artist": "作者",
        "brightnessvalue": "亮度值",
        "colorspace": "色彩空间",
        "componentsconfiguration": "组件配置",
        "compressedbitsperpixel": "每像素压缩位数",
        "contrast": "对比度",
        "copyright": "版权",
        "datetime": "日期时间",
        "datetimedigitized": "数字化时间",
        "datetimeoriginal": "拍摄时间",
        "digitalzoomratio": "数码变焦",
        "exifversion": "Exif 版本",
        "exposurebiasvalue": "曝光补偿",
        "exposuremode": "曝光模式",
        "exposureprogram": "曝光程序",
        "exposuretime": "曝光时间",
        "fnumber": "光圈",
        "flash": "闪光灯",
        "flashpixversion": "FlashPix 版本",
        "focallength": "焦距",
        "focallengthin35mmfilm": "等效焦距",
        "gpsaltitude": "海拔",
        "gpsaltituderef": "海拔参考",
        "gpsdatestamp": "GPS 日期",
        "gpsdestbearing": "目的地方位",
        "gpsdestbearingref": "目的地方位参考",
        "gpshpositioningerror": "水平定位误差",
        "gpsimgdirection": "拍摄方向",
        "gpsimgdirectionref": "拍摄方向参考",
        "gpslatitude": "纬度",
        "gpslatituderef": "纬度参考",
        "gpslongitude": "经度",
        "gpslongituderef": "经度参考",
        "gpsspeed": "速度",
        "gpsspeedref": "速度单位",
        "gpstimestamp": "GPS 时间",
        "gpsversion": "GPS 版本",
        "hostcomputer": "主机",
        "imageheight": "图片高度",
        "imagelength": "图片高度",
        "imagewidth": "图片宽度",
        "isoequivalent": "ISO",
        "isospeedratings": "ISO",
        "lensmake": "镜头厂商",
        "lensmodel": "镜头型号",
        "lensspecification": "镜头规格",
        "make": "设备厂商",
        "meteringmode": "测光模式",
        "model": "设备型号",
        "offsettime": "时区偏移",
        "offsettimedigitized": "数字化时区",
        "offsettimeoriginal": "拍摄时区",
        "orientation": "方向",
        "pixelheight": "像素高度",
        "pixelwidth": "像素宽度",
        "pixelxdimension": "像素宽度",
        "pixelydimension": "像素高度",
        "profiledatetime": "色彩配置时间",
        "saturation": "饱和度",
        "scene_capture_type": "场景类型",
        "scenecapturetype": "场景类型",
        "sensingmethod": "感光方式",
        "sharpness": "锐度",
        "shutterspeedvalue": "快门速度",
        "software": "软件",
        "subjectarea": "主体区域",
        "subsectime": "亚秒时间",
        "subsectimedigitized": "数字化亚秒",
        "subsectimeoriginal": "拍摄亚秒",
        "whitebalance": "白平衡",
        "whitebalancefinetune": "白平衡微调",
        "whitebalanceshift": "白平衡偏移",
        "wbrblevels": "白平衡偏移",
        "wbgrblevels": "白平衡偏移",
        "whitebalancerblevels": "白平衡偏移",
        "xresolution": "水平分辨率",
        "ycbcrpositioning": "YCbCr 定位",
        "yresolution": "垂直分辨率"
    ]

    static func chineseName(for key: String) -> String? {
        names[normalized(key)]
    }

    private static func normalized(_ key: String) -> String {
        key
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
