#if os(macOS)

import Foundation

enum AppTab: Hashable {
    case photos
    case settings
}

enum PhotoDetailState {
    case loading
    case loaded(PhotoMetadata)
    case failed(String)
}

struct LocalPhotoFile {
    let id: String
    let fileURL: URL
    let fileName: String
    let data: Data
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

struct PhotoAsset: Identifiable, Hashable {
    let id: String
    let localFile: LocalPhotoFile
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let displayName: String?

    nonisolated init(file: LocalPhotoFile) {
        self.id = file.id
        self.localFile = file
        self.creationDate = file.creationDate
        self.modificationDate = file.modificationDate
        self.pixelWidth = file.pixelWidth
        self.pixelHeight = file.pixelHeight
        self.displayName = file.fileName
    }

    static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#endif
