//
//  MetadataParsing.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import CoreLocation
import Foundation
import ImageIO

nonisolated enum MetadataParser {
    static func parse(url: URL, fallbackCoordinate: CLLocationCoordinate2D?) -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return PhotoMetadata(sections: [], coordinate: fallbackCoordinate)
        }

        let mappedData = try? Data(contentsOf: url, options: .mappedIfSafe)
        return parse(
            properties: properties,
            imageData: mappedData,
            fallbackCoordinate: fallbackCoordinate
        )
    }

    static func parse(data: Data, fallbackCoordinate: CLLocationCoordinate2D?) -> PhotoMetadata {
        guard !Task.isCancelled else {
            return PhotoMetadata(sections: [], coordinate: fallbackCoordinate)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return PhotoMetadata(sections: [], coordinate: fallbackCoordinate)
        }

        return parse(properties: properties, imageData: data, fallbackCoordinate: fallbackCoordinate)
    }

    private static func parse(
        properties: [String: Any],
        imageData: Data?,
        fallbackCoordinate: CLLocationCoordinate2D?
    ) -> PhotoMetadata {

        let coordinate = parseCoordinate(from: properties) ?? fallbackCoordinate
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

        guard !Task.isCancelled else {
            return PhotoMetadata(sections: sections, coordinate: coordinate)
        }
        sections.append(contentsOf: CameraMetadataSectionBuilder.sections(from: properties, imageData: imageData))
        guard !Task.isCancelled else {
            return PhotoMetadata(sections: sections, coordinate: coordinate)
        }
        sections.append(contentsOf: WhiteBalanceMetadataFallbackBuilder.sections(from: properties, existingSections: sections))

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

nonisolated enum WhiteBalanceMetadataFallbackBuilder {
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
            if let formatted = FujifilmMakerNoteParser.formattedWhiteBalanceFineTune(from: rawValue) {
                return formatted
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

enum MetadataKeyTranslator {
    nonisolated private static let names: [String: String] = [
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
        "flickerreduction": "闪烁抑制",
        "fujimodel": "Fuji 型号",
        "fujimodel2": "Fuji 型号 2",
        "filmmode": "胶片风格",
        "filmsimulation": "胶片风格",
        "filmsimulationmode": "胶片风格",
        "dynamicrange": "动态范围",
        "dynamicrangesetting": "动态范围设置",
        "drangepriority": "动态范围优先",
        "drangepriorityauto": "动态范围优先自动",
        "drangepriorityfixed": "动态范围优先固定",
        "autodynamicrange": "自动动态范围",
        "developmentdynamicrange": "冲洗动态范围",
        "prioritysettings": "对焦优先级",
        "focussettings": "对焦设置",
        "afcsettings": "AF-C 设置",
        "afspriority": "AF-S 优先级",
        "afcpriority": "AF-C 优先级",
        "focusmode2": "对焦模式 2",
        "preaf": "预对焦",
        "afareamode": "AF 区域模式",
        "afareapointsize": "AF 区域点大小",
        "afareazonesize": "AF 区域大小",
        "afcsetting": "AF-C 设置",
        "afctrackingsensitivity": "AF-C 跟踪灵敏度",
        "afcspeedtrackingsensitivity": "AF-C 速度跟踪灵敏度",
        "afczoneareaswitching": "AF-C 区域切换",
        "drivemode": "驱动模式",
        "drivespeed": "驱动速度",
        "colortemperature": "色温",
        "noisereduction": "降噪",
        "highisonoisereduction": "高 ISO 降噪",
        "clarity": "清晰度",
        "fujiflashmode": "闪光模式",
        "flashexposurecomp": "闪光曝光补偿",
        "macro": "微距",
        "focusmode": "对焦模式",
        "afmode": "AF 模式",
        "focuspixel": "对焦像素",
        "slowsync": "慢速同步",
        "exrauto": "EXR 自动",
        "exrmode": "EXR 模式",
        "multipleexposure": "多重曝光",
        "shadowtone": "阴影",
        "highlighttone": "高光",
        "lensmodulationoptimizer": "镜头像差校正",
        "graineffectroughness": "颗粒效果粗糙度",
        "colorchromeeffect": "Color Chrome 效果",
        "bwadjustment": "黑白暖冷",
        "bwmagentagreen": "黑白洋红/绿色",
        "graineffectsize": "颗粒效果尺寸",
        "cropmode": "裁切模式",
        "colorchromefxblue": "Color Chrome FX Blue",
        "autobracketing": "包围曝光",
        "sequencenumber": "序列号",
        "compositeimagemode": "合成图像模式",
        "advancedfilter": "高级滤镜",
        "colormode": "色彩模式",
        "blurwarning": "模糊警告",
        "focuswarning": "对焦警告",
        "exposurewarning": "曝光警告",
        "minfocallength": "最小焦距",
        "maxfocallength": "最大焦距",
        "maxapertureatminfocal": "最小焦距最大光圈",
        "maxapertureatmaxfocal": "最大焦距最大光圈",
        "imagestabilization": "防抖",
        "scenerecognition": "场景识别",
        "imagegeneration": "图像生成",
        "imagecount": "快门次数",
        "drivesettings": "驱动设置",
        "picturemode": "拍摄模式",
        "shuttertype": "快门模式",
        "whitebalancebracketing": "白平衡包围",
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
        "internalserialnumber": "内部序列号",
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
        "quality": "图像质量",
        "rollangle": "翻滚角",
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
        "version": "版本",
        "wbblue": "WB 蓝通道",
        "wbgreen": "WB 绿通道",
        "wbred": "WB 红通道",
        "whitebalance": "白平衡",
        "whitebalancefinetune": "白平衡微调",
        "whitebalanceshift": "白平衡偏移",
        "wbrblevels": "白平衡偏移",
        "wbgrblevels": "白平衡偏移",
        "whitebalancerblevels": "白平衡偏移",
        "numfaceelements": "人脸元素数量",
        "afilluminator": "AF 辅助灯",
        "afpointselected": "AF 点",
        "aftracking": "AF 跟踪",
        "antiblur": "防抖",
        "autoportraitframed": "自动人像构图",
        "colorcompensationfilter": "色彩补偿滤镜",
        "creativestyle": "创意风格",
        "dynamicrangeoptimizer": "动态范围优化",
        "electronicfrontcurtainshutter": "电子前帘快门",
        "fileformat": "文件格式",
        "hdr": "HDR",
        "jpegheifswitch": "JPEG/HEIF",
        "longexposurenoisereduction": "长曝光降噪",
        "rawfiletype": "图像质量",
        "releasemode": "释放模式",
        "sonymodelid": "SONY 型号 ID",
        "stepcropshooting": "裁切模式",
        "teleconverter": "增距镜",
        "xresolution": "水平分辨率",
        "ycbcrpositioning": "YCbCr 定位",
        "yresolution": "垂直分辨率"
    ]

    nonisolated private static let englishNamesByChineseName: [String: String] = [
        "AF-C 设置": "AF-C Settings",
        "AF 点": "AF Point",
        "AF 跟踪": "AF Tracking",
        "AF 辅助灯": "AF Illuminator",
        "AF 模式": "AF Mode",
        "Color Chrome 效果": "Color Chrome Effect",
        "EXR 模式": "EXR Mode",
        "Fuji 型号": "Fuji Model",
        "Fuji 型号 2": "Fuji Model 2",
        "Nikon 参数": "Nikon Parameters",
        "SONY 参数": "SONY Parameters",
        "SONY 型号 ID": "SONY Model ID",
        "Fujifilm 参数": "Fujifilm Parameters",
        "WB 红通道": "WB Red Channel",
        "WB 绿通道": "WB Green Channel",
        "WB 蓝通道": "WB Blue Channel",
        "作者": "Artist",
        "包围曝光": "Bracketing",
        "版本": "Version",
        "曝光模式": "Exposure Mode",
        "曝光程序": "Exposure Program",
        "曝光计数": "Exposure Count",
        "曝光补偿": "Exposure Bias",
        "曝光警告": "Exposure Warning",
        "曝光时间": "Exposure Time",
        "白平衡": "White Balance",
        "白平衡偏移": "White Balance Shift",
        "白平衡微调": "White Balance Fine Tune",
        "版权": "Copyright",
        "饱和度": "Saturation",
        "裁切模式": "Crop Mode",
        "测光模式": "Metering Mode",
        "长曝光降噪": "Long Exposure Noise Reduction",
        "场景类型": "Scene Type",
        "场景模式": "Scene Mode",
        "程序自动曝光": "Program AE",
        "尺寸": "Dimensions",
        "冲洗动态范围": "Development Dynamic Range",
        "地理位置": "Location",
        "等效焦距": "35mm Equivalent Focal Length",
        "低速同步": "Slow Sync",
        "对比度": "Contrast",
        "对焦警告": "Focus Warning",
        "对焦模式": "Focus Mode",
        "对焦设置": "Focus Settings",
        "对焦像素": "Focus Pixel",
        "对焦优先级": "Focus Priority",
        "动态 D-Lighting": "Active D-Lighting",
        "动态范围": "Dynamic Range",
        "动态范围优先": "D-Range Priority",
        "方向": "Orientation",
        "防抖": "Image Stabilization",
        "分辨率": "Resolution",
        "高级滤镜": "Advanced Filter",
        "高 ISO 降噪": "High ISO Noise Reduction",
        "高光": "Highlight",
        "高光色调": "Highlight Tone",
        "光圈": "Aperture",
        "光圈值": "Aperture Value",
        "海拔": "Altitude",
        "海拔参考": "Altitude Reference",
        "红眼校正": "Red-Eye Correction",
        "画质": "Image Quality",
        "机内处理": "In-Camera Processing",
        "机械快门": "Mechanical Shutter",
        "JPEG/HEIF": "JPEG/HEIF",
        "焦距": "Focal Length",
        "胶片风格": "Film Simulation",
        "胶片颗粒/色彩效果": "Film Grain/Color Effect",
        "降噪": "Noise Reduction",
        "接收器状态": "Receiver Status",
        "镜头厂商": "Lens Make",
        "镜头规格": "Lens Specification",
        "镜头类型": "Lens Type",
        "镜头型号": "Lens Model",
        "镜头信息": "Lens Information",
        "镜头像差校正": "Lens Modulation Optimizer",
        "镜头卡口": "Lens Mount",
        "镜头校正": "Lens Correction",
        "经度": "Longitude",
        "经度参考": "Longitude Reference",
        "颗粒效果尺寸": "Grain Effect Size",
        "颗粒效果粗糙度": "Grain Effect Roughness",
        "快门次数": "Shutter Count",
        "快门模式": "Shutter Mode",
        "快门速度": "Shutter Speed",
        "宽度": "Width",
        "连拍": "Continuous Shooting",
        "亮度值": "Brightness Value",
        "慢速同步": "Slow Sync",
        "模糊警告": "Blur Warning",
        "内部序列号": "Internal Serial Number",
        "拍摄方向": "Image Direction",
        "拍摄模式": "Shooting Mode",
        "拍摄时间": "Date Taken",
        "拍摄时区": "Original Time Zone",
        "拍摄亚秒": "Original Subsecond Time",
        "评分": "Rating",
        "清晰度": "Clarity",
        "色彩补偿滤镜": "Color Compensation Filter",
        "色彩": "Color",
        "色彩模式": "Color Mode",
        "色彩空间": "Color Space",
        "色彩配置时间": "Profile Date Time",
        "色调补偿": "Tone Compensation",
        "色温": "Color Temperature",
        "淡化": "Fade",
        "闪光灯": "Flash",
        "闪光曝光补偿": "Flash Exposure Compensation",
        "闪光模式": "Flash Mode",
        "释放模式": "Release Mode",
        "闪烁抑制": "Flicker Reduction",
        "设备厂商": "Make",
        "设备型号": "Model",
        "水平定位误差": "Horizontal Positioning Error",
        "水平分辨率": "X Resolution",
        "速度": "Speed",
        "速度单位": "Speed Reference",
        "同步模式": "Sync Mode",
        "图像生成": "Image Generation",
        "图像质量": "Image Quality",
        "纬度": "Latitude",
        "纬度参考": "Latitude Reference",
        "文件名": "File Name",
        "像素高度": "Pixel Height",
        "像素宽度": "Pixel Width",
        "相机配置": "Camera Profile",
        "序列号": "Serial Number",
        "旋转": "Rotation",
        "压缩": "Compression",
        "颜色": "Color",
        "阴影": "Shadow",
        "优化校准": "Picture Control",
        "主机": "Host Computer",
        "主体区域": "Subject Area",
        "自动动态范围": "Auto Dynamic Range",
        "自动人像构图": "Auto Portrait Framing",
        "自拍": "Self Timer",
        "组件配置": "Components Configuration",
        "最小焦距": "Minimum Focal Length",
        "最大焦距": "Maximum Focal Length",
        "最小焦距最大光圈": "Maximum Aperture at Minimum Focal Length",
        "最大焦距最大光圈": "Maximum Aperture at Maximum Focal Length",
        "软件": "Software",
        "锐度": "Sharpness",
        "翻滚角": "Roll Angle",
        "人脸检测": "Faces Detected",
        "人脸元素数量": "Face Element Count",
        "数字化时间": "Date Digitized",
        "数字化时区": "Digitized Time Zone",
        "数字化亚秒": "Digitized Subsecond Time",
        "日期时间": "Date Time",
        "时区偏移": "Time Zone Offset",
        "目的地方位": "Destination Bearing",
        "目的地方位参考": "Destination Bearing Reference",
        "垂直分辨率": "Y Resolution",
        "亚秒时间": "Subsecond Time"
    ]

    nonisolated static func chineseName(for key: String) -> String? {
        names[normalized(key)]
    }

    nonisolated static func englishName(for key: String) -> String? {
        englishNamesByChineseName[key]
    }

    nonisolated private static func normalized(_ key: String) -> String {
        key
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
