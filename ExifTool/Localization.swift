//
//  Localization.swift
//  ExifTool
//
//  Created by Codex on 2026/4/18.
//

import Foundation

enum AppLocalization {
    nonisolated static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    nonisolated static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

enum MetadataDisplayLocalizer {
    static func sectionTitle(_ section: MetadataSection, showsChinese: Bool) -> String {
        if showsChinese {
            return chineseSectionTitle(for: section) ?? section.title
        }

        return englishSectionTitle(for: section) ?? section.title
    }

    static func keyTitle(_ key: String, showsChinese: Bool) -> String {
        if showsChinese {
            return MetadataKeyTranslator.chineseName(for: key) ?? key
        }

        return MetadataKeyTranslator.englishName(for: key) ?? key
    }

    static func valueText(_ value: String, showsChinese: Bool) -> String {
        guard showsChinese else {
            return value
        }

        return value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { localizedValueLine(String($0)) }
            .joined(separator: "\n")
    }

    private static func localizedValueLine(_ line: String) -> String {
        guard let separatorRange = line.range(of: ": ") else {
            return localizedValueComponent(line)
        }

        let key = String(line[..<separatorRange.lowerBound])
        let value = String(line[separatorRange.upperBound...])
        let localizedKey = MetadataKeyTranslator.chineseName(for: key) ?? key
        return "\(localizedKey): \(localizedValueComponent(value))"
    }

    private static func localizedValueComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let mapped = chineseValueNames[trimmed] {
            return mapped
        }

        if let parenthesisRange = trimmed.range(of: " (") {
            let head = String(trimmed[..<parenthesisRange.lowerBound])
            let suffix = String(trimmed[parenthesisRange.lowerBound...])
            if let mapped = chineseValueNames[head] {
                return mapped + suffix
            }
        }

        return value
    }

    private static let chineseValueNames: [String: String] = [
        "Auto": "自动",
        "Auto (white priority)": "自动（白色优先）",
        "Auto (ambiance priority)": "自动（氛围优先）",
        "Daylight": "日光",
        "Cloudy": "阴天",
        "Daylight Fluorescent": "日光荧光灯",
        "Day White Fluorescent": "昼白荧光灯",
        "White Fluorescent": "白色荧光灯",
        "Warm White Fluorescent": "暖白荧光灯",
        "Living Room Warm White Fluorescent": "室内暖白荧光灯",
        "Incandescent": "白炽灯",
        "Flash": "闪光灯",
        "Underwater": "水下",
        "Custom": "自定义",
        "Custom2": "自定义 2",
        "Custom3": "自定义 3",
        "Custom4": "自定义 4",
        "Custom5": "自定义 5",
        "Kelvin": "色温",
        "n/a": "无",
        "Standard": "标准",
        "Manual": "手动",
        "Standard (100%)": "标准 (100%)",
        "Wide": "宽动态",
        "Wide1 (230%)": "宽动态 1 (230%)",
        "Wide2 (400%)": "宽动态 2 (400%)",
        "Film Simulation": "胶片模拟",
        "Weak": "弱",
        "Strong": "强",
        "Plus": "增强",
        "Off": "关闭",
        "On": "开启",
        "No": "否",
        "None": "无",
        "Good": "正常",
        "Out of focus": "未合焦",
        "Bad exposure": "曝光异常",
        "Blur Warning": "模糊警告",
        "Release": "释放优先",
        "Focus": "对焦优先",
        "Front": "前方",
        "Center": "中央",
        "Set 1 (multi-purpose)": "设置 1（通用）",
        "Set 2 (ignore obstacles)": "设置 2（忽略障碍）",
        "Set 3 (accelerating subject)": "设置 3（加速主体）",
        "Set 4 (suddenly appearing subject)": "设置 4（突然出现主体）",
        "Set 5 (erratic motion)": "设置 5（不规则运动）",
        "Single": "单张",
        "Continuous Low": "低速连拍",
        "Continuous High": "高速连拍",
        "Single Point": "单点",
        "Zone": "区域",
        "Wide/Tracking": "广域/跟踪",
        "AF-M": "手动对焦",
        "AF-S": "单次 AF",
        "AF-C": "连续 AF",
        "Mechanical": "机械快门",
        "Electronic": "电子快门",
        "Electronic (long shutter speed)": "电子快门（长快门）",
        "Electronic Front Curtain": "电子前帘",
        "Optical": "光学防抖",
        "Sensor-shift": "机身防抖",
        "OIS Lens": "镜头防抖",
        "IBIS/OIS + DIS": "机身/镜头 + 数码防抖",
        "Digital": "数码防抖",
        "On (mode 1, continuous)": "开启（模式 1，连续）",
        "On (mode 2, shooting only)": "开启（模式 2，仅拍摄）",
        "Original Image": "原始图像",
        "Re-developed from RAW": "RAW 重新冲洗",
        "Portrait Image": "人像",
        "Night Portrait": "夜景人像",
        "Backlit Portrait": "逆光人像",
        "Landscape Image": "风景",
        "Night Scene": "夜景",
        "Macro": "微距",
        "Portrait": "人像",
        "Landscape": "风景",
        "Sports": "运动",
        "Program AE": "程序自动曝光",
        "Aperture-priority AE": "光圈优先 AE",
        "Shutter speed priority AE": "快门优先 AE",
        "Classic Chrome": "经典正片",
        "Classic Negative": "经典负片",
        "Bleach Bypass": "漂白效果",
        "Nostalgic Neg": "怀旧负片",
        "Reala ACE": "REALA ACE",
        "Pro Neg. Std": "PRO Neg. Std",
        "Pro Neg. Hi": "PRO Neg. Hi",
        "Eterna": "ETERNA",
        "F0/Standard (Provia)": "标准/PROVIA",
        "F2/Fujichrome (Velvia)": "Velvia/鲜艳",
        "F4/Velvia": "Velvia/鲜艳"
    ]

    private static func chineseSectionTitle(for section: MetadataSection) -> String? {
        switch section.id {
        case "fujifilm-parameters":
            return "Fujifilm 参数"
        case "fujifilm-white-balance", "fujifilm-group-white-balance":
            return "富士白平衡"
        case "fujifilm-rendering", "fujifilm-group-rendering":
            return "富士色彩/动态范围"
        case "fujifilm-focus-drive", "fujifilm-group-focus-drive":
            return "富士 AF/驱动"
        case "fujifilm-camera", "fujifilm-group-camera":
            return "富士机身/处理"
        case "nikon-parameters":
            return "Nikon 参数"
        case "white-balance-fallback":
            return "白平衡"
        default:
            return nil
        }
    }

    private static func englishSectionTitle(for section: MetadataSection) -> String? {
        switch section.id {
        case "fujifilm-parameters":
            return "Fujifilm Parameters"
        case "fujifilm-white-balance", "fujifilm-group-white-balance":
            return "Fujifilm White Balance"
        case "fujifilm-rendering", "fujifilm-group-rendering":
            return "Fujifilm Color/DR"
        case "fujifilm-focus-drive", "fujifilm-group-focus-drive":
            return "Fujifilm AF/Drive"
        case "fujifilm-camera", "fujifilm-group-camera":
            return "Fujifilm Camera"
        case "nikon-parameters":
            return "Nikon Parameters"
        case "white-balance-fallback":
            return "White Balance"
        default:
            return MetadataKeyTranslator.englishName(for: section.title)
        }
    }
}
