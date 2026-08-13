#if os(macOS)

import SwiftUI

struct MacSettingsTabView: View {
    @AppStorage("readOnlyMode") private var readOnlyMode = true

    var body: some View {
        NavigationStack {
            Form {
                MacReadOnlySettingsSection(readOnlyMode: $readOnlyMode)
                MacAppVersionSettingsSection()
            }
            .navigationTitle("设置")
        }
        .frame(width: 480)
    }
}

#endif
