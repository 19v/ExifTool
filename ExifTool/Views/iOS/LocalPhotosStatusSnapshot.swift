#if os(iOS)

import Foundation

struct LocalPhotosStatusSnapshot {
    let text: String
    let state: PhotoLibraryViewModel.LocalPhotosSummaryState?
    let localPhotosCount: Int?
    let localAlbumsCount: Int?
}

#endif
