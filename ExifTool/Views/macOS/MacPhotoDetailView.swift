#if os(macOS)

import SwiftUI

struct MacPhotoDetailView: View {
    let asset: PhotoAsset

    @State private var showsChineseKeys = MetadataLanguagePreference.defaultShowsChineseKeys

    var body: some View {
        MacPhotoDetailPage(
            asset: asset,
            showsChineseKeys: $showsChineseKeys,
            navigationTitle: asset.displayName ?? AppLocalization.string("photoDetail.title")
        )
    }
}

enum MetadataLanguagePreference {
    static var defaultShowsChineseKeys: Bool {
        guard let preferredLanguage = Locale.preferredLanguages.first else {
            return false
        }

        return Locale(identifier: preferredLanguage).language.languageCode?.identifier == "zh"
    }
}

#endif
