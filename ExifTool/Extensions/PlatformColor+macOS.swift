//
//  PlatformColor+macOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import SwiftUI

extension Color {
    static var platformSecondaryBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

#endif
