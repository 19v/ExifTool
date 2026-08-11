#if os(iOS)

import SwiftUI

@main
struct ExifToolApp: App {
    var body: some Scene {
        WindowGroup {
            IOSRootView()
        }
    }
}

#endif
