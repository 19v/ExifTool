#if os(macOS)

import SwiftUI

struct ComparisonRow: Identifiable {
    let key: String
    let label: String
    let leftValue: String
    let rightValue: String
    let isDifferent: Bool

    var id: String { key }
}

struct ComparisonSection: Identifiable {
    let title: String
    let rows: [ComparisonRow]

    var id: String { title }
}

struct DifferenceSummaryItem: Identifiable {
    let key: String
    let label: String
    let leftValue: String
    let rightValue: String

    var id: String { key }
}

enum MacPhotoComparisonFeedback: Equatable {
    case copied
    case exported(URL)
    case exportFailed

    var message: String {
        switch self {
        case .copied:
            return "对比结果已复制到剪贴板"
        case .exported(let url):
            return "已导出到 \(url.lastPathComponent)"
        case .exportFailed:
            return "导出失败，请稍后重试"
        }
    }

    var color: Color {
        switch self {
        case .exportFailed:
            return .red
        case .copied, .exported:
            return .secondary
        }
    }
}

#endif
