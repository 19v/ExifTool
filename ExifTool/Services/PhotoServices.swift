//
//  PhotoServices.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import CoreLocation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

enum PhotoSearchIndex {
    static func text(for asset: PhotoAsset) -> String {
        var parts = [
            asset.id,
            "\(asset.pixelWidth)x\(asset.pixelHeight)"
        ]

        if let displayName = asset.displayName {
            parts.append(displayName)
        }

        if let creationDate = asset.creationDate {
            parts.append(creationDate.formatted(date: .numeric, time: .shortened))
        }

        if let modificationDate = asset.modificationDate {
            parts.append(modificationDate.formatted(date: .numeric, time: .shortened))
        }

        return parts.joined(separator: " ")
    }
}

enum PhotoFileImporter {
    nonisolated static func importAssets(from urls: [URL]) -> [PhotoAsset] {
        urls.compactMap(importAsset)
    }

    nonisolated private static func importAsset(from url: URL) -> PhotoAsset? {
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

        guard let data = try? Data(contentsOf: fileURL),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let file = LocalPhotoFile(
            id: fileURL.path(),
            fileURL: fileURL,
            fileName: resourceValues?.name ?? fileURL.lastPathComponent,
            data: data,
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
        switch asset.source {
        case .photoLibrary(let photoLibraryAsset):
            return await thumbnail(for: photoLibraryAsset, size: size)
        case .file(let file):
            return thumbnail(from: file.data, maxPixelLength: max(size.width, size.height))
        }
    }

    static func metadata(for asset: PhotoAsset, allowNetwork: Bool) async -> PhotoDetailState {
        switch asset.source {
        case .photoLibrary(let photoLibraryAsset):
            return await metadata(for: photoLibraryAsset, allowNetwork: allowNetwork)
        case .file(let file):
            return .loaded(MetadataParser.parse(data: file.data, fallbackLocation: nil))
        }
    }

    private static func thumbnail(for asset: PHAsset, size: CGSize) async -> PlatformImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func metadata(for asset: PHAsset, allowNetwork: Bool) async -> PhotoDetailState {
        if let resource = imageResource(for: asset) {
            do {
                let data = try await resourceData(for: resource, allowNetwork: allowNetwork)
                return .loaded(MetadataParser.parse(data: data, fallbackLocation: asset.location))
            } catch {
                if let fallback = await imageManagerData(for: asset, allowNetwork: allowNetwork) {
                    return .loaded(MetadataParser.parse(data: fallback, fallbackLocation: asset.location))
                }

                if !allowNetwork {
                    return .needsDownload("这张照片的原图可能只保存在 iCloud。默认离线模式不会自动下载，点击下方按钮后仅下载当前照片。")
                }

                return .failed(error.localizedDescription)
            }
        }

        if let data = await imageManagerData(for: asset, allowNetwork: allowNetwork) {
            return .loaded(MetadataParser.parse(data: data, fallbackLocation: asset.location))
        }

        if !allowNetwork {
            return .needsDownload("这张照片的原图可能只保存在 iCloud。默认离线模式不会自动下载，点击下方按钮后仅下载当前照片。")
        }

        return .failed("没有找到可读取的本机照片资源。")
    }

    private static func thumbnail(from data: Data, maxPixelLength: CGFloat) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(ceil(maxPixelLength)))
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        #if os(iOS)
        return UIImage(cgImage: cgImage)
        #elseif os(macOS)
        return NSImage(cgImage: cgImage, size: .zero)
        #endif
    }

    private static func imageResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredTypes: [PHAssetResourceType] = [.fullSizePhoto, .photo, .alternatePhoto]

        for type in preferredTypes {
            if let resource = resources.first(where: { $0.type == type }) {
                return resource
            }
        }

        return resources.first
    }

    private static func resourceData(for resource: PHAssetResource, allowNetwork: Bool) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var result = Data()
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = allowNetwork

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    result.append(data)
                },
                completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            )
        }
    }

    private static func imageManagerData(for asset: PHAsset, allowNetwork: Bool) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = allowNetwork

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                continuation.resume(returning: !allowNetwork && isInCloud ? nil : data)
            }
        }
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
