//
//  Models.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

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

    nonisolated init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.source = .photoLibrary(asset)
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.location = asset.location
        self.displayName = nil
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
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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

    init(collection: PHAssetCollection, assetCount: Int) {
        self.id = collection.localIdentifier
        self.title = collection.localizedTitle ?? "未命名相册"
        self.assetCount = assetCount
        self.collection = collection
    }

    static func == (lhs: PhotoAlbum, rhs: PhotoAlbum) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum PhotoDetailState {
    case loading
    case loaded(PhotoMetadata)
    case needsDownload(String)
    case failed(String)
}

struct PhotoMetadata {
    let sections: [MetadataSection]
    let coordinate: CLLocationCoordinate2D?
}

struct MetadataSection: Identifiable {
    let id: String
    let title: String
    let items: [MetadataItem]
}

struct MetadataItem: Identifiable {
    let id: String
    let key: String
    let value: String
}
