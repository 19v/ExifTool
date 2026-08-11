#if os(macOS)

import SwiftUI

struct MacSettingsTabView: View {
    @Binding var readOnlyMode: Bool

    var body: some View {
        NavigationStack {
            Form {
                MacReadOnlySettingsSection(readOnlyMode: $readOnlyMode)
                MacAppVersionSettingsSection()
            }
            .navigationTitle("设置")
        }
    }
}

#endif
