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
            return AppLocalization.string("mac.comparison.copied")
        case .exported(let url):
            return AppLocalization.string("mac.comparison.exported", url.lastPathComponent)
        case .exportFailed:
            return AppLocalization.string("mac.comparison.exportFailed")
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
