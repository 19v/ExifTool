#if os(iOS)

//
//  LocalPhotosStatusBanner.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

struct LocalPhotosStatusBanner: View {
    enum Emphasis {
        case compact
        case card
        case floating
    }

    let snapshot: LocalPhotosStatusSnapshot
    let emphasis: Emphasis

    var body: some View {
        LocalPhotosStatusContent(snapshot: snapshot)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if emphasis == .floating {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
        .shadow(
            color: emphasis == .floating ? .black.opacity(0.12) : .clear,
            radius: emphasis == .floating ? 16 : 0,
            y: emphasis == .floating ? 8 : 0
        )
        .padding(.horizontal, horizontalInset)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
    }

    private var backgroundStyle: some ShapeStyle {
        switch emphasis {
        case .compact:
            return AnyShapeStyle(Color.platformSecondaryBackground)
        case .card:
            return AnyShapeStyle(Color.platformSecondaryBackground)
        case .floating:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var horizontalInset: CGFloat {
        switch emphasis {
        case .compact, .card:
            return 12
        case .floating:
            return 16
        }
    }

    private var topInset: CGFloat {
        switch emphasis {
        case .compact:
            return 8
        case .card:
            return 0
        case .floating:
            return 8
        }
    }

    private var bottomInset: CGFloat {
        switch emphasis {
        case .compact:
            return 6
        case .card:
            return 0
        case .floating:
            return 6
        }
    }
}

#endif
