#if os(macOS)

import SwiftUI

struct MacSettingsTabView: View {
    var body: some View {
        NavigationStack {
            Form {
                MacAppVersionSettingsSection()
            }
            .navigationTitle("设置")
        }
        .frame(width: 480)
    }
}

#endif
