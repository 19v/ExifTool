#if os(macOS)

import Foundation

nonisolated enum PhotoDetailState: Equatable, Sendable {
    case loading
    case loaded(PhotoMetadata)
    case failed(String)
}

nonisolated struct LocalPhotoFile: Sendable {
    let id: String
    let fileURL: URL
    let fileName: String
    let data: Data?
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

nonisolated struct PhotoAsset: Identifiable, Hashable, Sendable {
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
        lhs.id == rhs.id &&
        lhs.localFile.fileURL == rhs.localFile.fileURL &&
        lhs.creationDate == rhs.creationDate &&
        lhs.modificationDate == rhs.modificationDate &&
        lhs.pixelWidth == rhs.pixelWidth &&
        lhs.pixelHeight == rhs.pixelHeight &&
        lhs.displayName == rhs.displayName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(localFile.fileURL)
        hasher.combine(creationDate)
        hasher.combine(modificationDate)
        hasher.combine(pixelWidth)
        hasher.combine(pixelHeight)
        hasher.combine(displayName)
    }
}

#endif
