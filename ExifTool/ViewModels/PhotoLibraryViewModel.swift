//
//  PhotoLibraryViewModel.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import Combine
import Photos

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    enum AccessScope {
        case unknown
        case limited
        case full
        case denied
    }
    
    enum AuthorizationState {
        case unknown
        case limited
        case authorized
        case denied
        case empty
    }
    
    @Published private(set) var accessScope: AccessScope = .unknown
    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var assets: [PhotoAsset] = []
    @Published private(set) var albums: [PhotoAlbum] = []
    
    func prepare() async {
        await refresh()
    }
    
    func refresh() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            loadAssets(for: newStatus)
        default:
            loadAssets(for: status)
        }
    }
    
    private func loadAssets(for status: PHAuthorizationStatus) {
        switch status {
        case .authorized:
            accessScope = .full
            authorizationState = .authorized
        case .limited:
            accessScope = .limited
            authorizationState = .limited
        case .denied, .restricted:
            accessScope = .denied
            authorizationState = .denied
            assets = []
            albums = []
            return
        case .notDetermined:
            accessScope = .unknown
            authorizationState = .unknown
            assets = []
            albums = []
            return
        @unknown default:
            accessScope = .denied
            authorizationState = .denied
            assets = []
            albums = []
            return
        }
        
        assets = Self.fetchImageAssets()
        albums = Self.fetchImageAlbums()
        if assets.isEmpty {
            authorizationState = .empty
        }
    }
    
    static func fetchImageAssets(in collection: PHAssetCollection? = nil) -> [PhotoAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let result: PHFetchResult<PHAsset>
        if let collection {
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: options)
        }
        
        var fetchedAssets: [PhotoAsset] = []
        fetchedAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetchedAssets.append(PhotoAsset(asset: asset))
        }
        
        return fetchedAssets
    }
    
    private static func fetchImageAlbums() -> [PhotoAlbum] {
        let imageOptions = PHFetchOptions()
        imageOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        var albums: [PhotoAlbum] = []
        var seenIdentifiers = Set<String>()
        
        func appendAlbums(from result: PHFetchResult<PHAssetCollection>) {
            result.enumerateObjects { collection, _, _ in
                guard !seenIdentifiers.contains(collection.localIdentifier) else {
                    return
                }
                
                let count = PHAsset.fetchAssets(in: collection, options: imageOptions).count
                guard count > 0 else {
                    return
                }
                
                seenIdentifiers.insert(collection.localIdentifier)
                albums.append(PhotoAlbum(collection: collection, assetCount: count))
            }
        }
        
        appendAlbums(from: PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil))
        appendAlbums(from: PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil))
        
        return albums.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
