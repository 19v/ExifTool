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

    private static func chineseSectionTitle(for section: MetadataSection) -> String? {
        switch section.id {
        case "fujifilm-parameters":
            return "Fujifilm 参数"
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
        case "nikon-parameters":
            return "Nikon Parameters"
        case "white-balance-fallback":
            return "White Balance"
        default:
            return MetadataKeyTranslator.englishName(for: section.title)
        }
    }
}
