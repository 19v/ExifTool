//
//  PlatformView+iOS.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(iOS)

import SwiftUI

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    func platformDetailPagingStyle() -> some View {
        tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    @ViewBuilder
    func platformTabBarHidden() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}

#endif

