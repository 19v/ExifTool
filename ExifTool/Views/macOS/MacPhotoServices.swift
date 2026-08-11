#if os(macOS)

import AppKit
import CoreLocation
import Foundation
import ImageIO
import UniformTypeIdentifiers

typealias PlatformImage = NSImage

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
        thumbnail(from: asset.localFile, maxPixelLength: max(size.width, size.height))
    }

    static func previewImage(for asset: PhotoAsset, size: CGSize) async -> PlatformImage? {
        thumbnail(from: asset.localFile, maxPixelLength: max(size.width, size.height))
    }

    static func metadata(for asset: PhotoAsset, allowNetwork: Bool) async -> PhotoDetailState {
        .loaded(MetadataParser.parse(url: asset.localFile.fileURL, fallbackLocation: nil))
    }

    static func shareablePhotoURL(for asset: PhotoAsset, allowNetwork: Bool) async throws -> URL {
        asset.localFile.fileURL
    }

    private static func thumbnail(from file: LocalPhotoFile, maxPixelLength: CGFloat) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(ceil(maxPixelLength)))
        ]

        guard let source = CGImageSourceCreateWithURL(file.fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: .zero)
    }
}

enum LocationFormatter {
    static func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
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
