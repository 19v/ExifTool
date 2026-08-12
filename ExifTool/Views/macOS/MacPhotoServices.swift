#if os(macOS)

import AppKit
import CoreLocation
import Foundation
import ImageIO
import UniformTypeIdentifiers

typealias PlatformImage = NSImage

@MainActor
private final class LocalThumbnailMemoryCache {
    static let shared = LocalThumbnailMemoryCache()

    private let images = NSCache<NSString, NSImage>()

    private init() {
        images.countLimit = 180
        images.totalCostLimit = 64 * 1_024 * 1_024
    }

    func image(forKey key: String) -> NSImage? {
        images.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, forKey key: String, pixelWidth: Int, pixelHeight: Int) {
        images.setObject(image, forKey: key as NSString, cost: pixelWidth * pixelHeight * 4)
    }
}

enum PhotoFileImporter {
    nonisolated static func importAssets(from urls: [URL]) -> [PhotoAsset] {
        urls.compactMap(importAsset)
    }

    nonisolated static func importAsset(from url: URL) -> PhotoAsset? {
        let fileURL = url.standardizedFileURL
        let resourceValues = try? fileURL.resourceValues(forKeys: [
            .contentTypeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .nameKey
        ])

        if let contentType = resourceValues?.contentType, !contentType.conforms(to: .image) {
            return nil
        }

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let file = LocalPhotoFile(
            id: fileURL.path(),
            fileURL: fileURL,
            fileName: resourceValues?.name ?? fileURL.lastPathComponent,
            data: nil,
            creationDate: resourceValues?.creationDate,
            modificationDate: resourceValues?.contentModificationDate,
            pixelWidth: properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
            pixelHeight: properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        )

        return PhotoAsset(file: file)
    }
}

enum PhotoLoader {
    static func thumbnail(for asset: PhotoAsset, size: CGSize) async -> PlatformImage? {
        await thumbnail(from: asset.localFile, maxPixelLength: max(size.width, size.height))
    }

    static func previewImage(for asset: PhotoAsset, size: CGSize) async -> PlatformImage? {
        await thumbnail(from: asset.localFile, maxPixelLength: max(size.width, size.height))
    }

    static func metadata(for asset: PhotoAsset, allowNetwork: Bool) async -> PhotoDetailState {
        let fileURL = asset.localFile.fileURL
        let metadata = await MediaProcessing.run {
            MetadataParser.parse(url: fileURL, fallbackCoordinate: nil)
        }
        return .loaded(metadata)
    }

    static func shareablePhotoURL(for asset: PhotoAsset, allowNetwork: Bool) async throws -> URL {
        asset.localFile.fileURL
    }

    private static func thumbnail(from file: LocalPhotoFile, maxPixelLength: CGFloat) async -> PlatformImage? {
        let cacheKey = localThumbnailCacheKey(for: file, maxPixelLength: maxPixelLength)
        if let cachedImage = LocalThumbnailMemoryCache.shared.image(forKey: cacheKey) {
            return cachedImage
        }

        let fileURL = file.fileURL
        let data = file.data
        guard let cgImage = await MediaProcessing.run(operation: {
            ImageThumbnailDecoder.decode(fileURL: fileURL, data: data, maxPixelLength: maxPixelLength)
        }) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: .zero)
        LocalThumbnailMemoryCache.shared.insert(
            image,
            forKey: cacheKey,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height
        )
        return image
    }

    private static func localThumbnailCacheKey(for file: LocalPhotoFile, maxPixelLength: CGFloat) -> String {
        let modificationTimestamp = file.modificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(file.id)|\(Int(ceil(maxPixelLength)))|\(modificationTimestamp)"
    }
}

enum LocationFormatter {
    nonisolated static func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        let latitude = String(format: "%.6f", coordinate.latitude)
        let longitude = String(format: "%.6f", coordinate.longitude)
        return "\(latitude), \(longitude)"
    }
}

enum MapDestination {
    case appleMaps
    case amap
    case googleMaps

    func url(for coordinate: CLLocationCoordinate2D) -> URL {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude

        switch self {
        case .appleMaps:
            return encodedURL("http://maps.apple.com/?ll=\(latitude),\(longitude)&q=照片位置")
        case .amap:
            return encodedURL("iosamap://viewMap?sourceApplication=ExifTool&poiname=照片位置&lat=\(latitude)&lon=\(longitude)&dev=0")
        case .googleMaps:
            return encodedURL("comgooglemaps://?q=\(latitude),\(longitude)&center=\(latitude),\(longitude)")
        }
    }

    private func encodedURL(_ value: String) -> URL {
        guard let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedValue) else {
            return URL(string: "http://maps.apple.com/")!
        }

        return url
    }
}

#endif
