//
//  PlatformColor+iOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

import SwiftUI

extension Color {
    static var platformSecondaryBackground: Color {
        Color(.secondarySystemBackground)
    }
}

#endif

