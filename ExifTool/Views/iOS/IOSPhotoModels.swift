#if os(iOS)

import CoreLocation
import Foundation
import Photos

enum AppTab: Hashable {
    case photos
    case picker
    case albums
    case settings
    case search
}

enum PhotoDetailState {
    case loading
    case loaded(PhotoMetadata)
    case needsDownload(String)
    case failed(String)
}

struct LocalPhotoFile {
    let id: String
    let fileURL: URL
    let fileName: String
    let data: Data?
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

struct PhotoAsset: Identifiable, Hashable {
    enum Source {
        case photoLibrary(PHAsset)
        case file(LocalPhotoFile)
    }

    let id: String
    let source: Source
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let location: CLLocation?
    let displayName: String?

    nonisolated init(asset: PHAsset, displayName: String? = nil) {
        self.id = asset.localIdentifier
        self.source = .photoLibrary(asset)
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.location = asset.location
        self.displayName = displayName
    }

    nonisolated init(file: LocalPhotoFile) {
        self.id = file.id
        self.source = .file(file)
        self.creationDate = file.creationDate
        self.modificationDate = file.modificationDate
        self.pixelWidth = file.pixelWidth
        self.pixelHeight = file.pixelHeight
        self.location = nil
        self.displayName = file.fileName
    }

    static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool {
        lhs.id == rhs.id &&
        lhs.creationDate == rhs.creationDate &&
        lhs.modificationDate == rhs.modificationDate &&
        lhs.pixelWidth == rhs.pixelWidth &&
        lhs.pixelHeight == rhs.pixelHeight &&
        lhs.location?.coordinate.latitude == rhs.location?.coordinate.latitude &&
        lhs.location?.coordinate.longitude == rhs.location?.coordinate.longitude &&
        lhs.displayName == rhs.displayName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(creationDate)
        hasher.combine(modificationDate)
        hasher.combine(pixelWidth)
        hasher.combine(pixelHeight)
        hasher.combine(location?.coordinate.latitude)
        hasher.combine(location?.coordinate.longitude)
        hasher.combine(displayName)
    }

    var photoLibraryAsset: PHAsset? {
        guard case .photoLibrary(let asset) = source else {
            return nil
        }

        return asset
    }

    var localFile: LocalPhotoFile? {
        guard case .file(let file) = source else {
            return nil
        }

        return file
    }
}

struct PhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let assetCount: Int
    let collection: PHAssetCollection

    nonisolated init(collection: PHAssetCollection, assetCount: Int) {
        self.id = collection.localIdentifier
        self.title = collection.localizedTitle ?? AppLocalization.string("album.untitled")
        self.assetCount = assetCount
        self.collection = collection
    }

    static func == (lhs: PhotoAlbum, rhs: PhotoAlbum) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.assetCount == rhs.assetCount
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(assetCount)
    }
}

#endif
