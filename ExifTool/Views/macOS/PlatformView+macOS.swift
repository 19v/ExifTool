//
//  PlatformView+macOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import SwiftUI

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        self
    }

    @ViewBuilder
    func platformDetailPagingStyle() -> some View {
        self
    }

    @ViewBuilder
    func platformTabBarHidden() -> some View {
        self
    }
}

#endif

