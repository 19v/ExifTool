#if os(iOS)

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
import CoreTransferable
internal import PhotosUI
import SwiftUI
import UIKit
typealias PlatformImage = UIImage
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
        urls.compactMap { importAsset(from: $0) }
    }

    nonisolated static func importAsset(from data: Data, suggestedFileName: String? = nil, id: String = UUID().uuidString) -> PhotoAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let file = LocalPhotoFile(
            id: id,
            fileURL: URL(fileURLWithPath: "/picked/\(id)"),
            fileName: suggestedFileName ?? AppLocalization.string("photoFileImporter.pickedImage"),
            data: data,
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
            pixelHeight: properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        )

        return PhotoAsset(file: file)
    }

    nonisolated static func importAsset(
        from url: URL,
        id: String? = nil,
        suggestedFileName: String? = nil
    ) -> PhotoAsset? {
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
            id: id ?? fileURL.path(),
            fileURL: fileURL,
            fileName: suggestedFileName ?? resourceValues?.name ?? fileURL.lastPathComponent,
            data: nil,
            creationDate: resourceValues?.creationDate,
            modificationDate: resourceValues?.contentModificationDate,
            pixelWidth: properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
            pixelHeight: properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        )

        return PhotoAsset(file: file)
    }

    nonisolated static func importAssetCopyingToTemporaryStorage(from url: URL) -> PhotoAsset? {
        guard let temporaryURL = try? PhotoResourceFileWriter.copyToTemporaryFile(
            sourceURL: url,
            directoryName: PhotoTemporaryFileStore.importsDirectoryName,
            fileName: url.lastPathComponent
        ) else {
            return nil
        }

        guard let asset = importAsset(from: temporaryURL, suggestedFileName: url.lastPathComponent) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            return nil
        }
        return asset
    }
}

enum PhotoTemporaryFileStore {
    nonisolated static let importsDirectoryName = "ExifTool-Imports"
    nonisolated static let metadataDirectoryName = "ExifTool-Metadata"
    nonisolated static let shareDirectoryName = "ExifTool-Share"
    nonisolated private static let managedDirectoryNames = [
        importsDirectoryName,
        metadataDirectoryName,
        shareDirectoryName
    ]

    nonisolated static func cleanupStaleFiles(olderThan maximumAge: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        let cutoffDate = Date().addingTimeInterval(-maximumAge)

        for directoryName in managedDirectoryNames {
            let directoryURL = managedDirectoryURL(named: directoryName)
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in fileURLs {
                let modificationDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if modificationDate.map({ $0 < cutoffDate }) ?? true {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        }
    }

    nonisolated static func removeIfManaged(_ fileURL: URL) {
        guard managedDirectoryNames.contains(where: { contains(fileURL, in: $0) }) else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    nonisolated static func isShareFile(_ fileURL: URL) -> Bool {
        contains(fileURL, in: shareDirectoryName)
    }

    nonisolated private static func contains(_ fileURL: URL, in directoryName: String) -> Bool {
        fileURL.standardizedFileURL.deletingLastPathComponent() == managedDirectoryURL(named: directoryName).standardizedFileURL
    }

    nonisolated private static func managedDirectoryURL(named directoryName: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: directoryName, directoryHint: .isDirectory)
    }
}

private final class CancellablePhotoRequestState<Value, RequestToken>: @unchecked Sendable {
    private enum Completion {
        case pending
        case finished(Value)
    }

    private let lock = NSLock()
    nonisolated(unsafe) private let cancellationValue: Value
    private let cancelRequest: @Sendable (RequestToken) -> Void
    nonisolated(unsafe) private var completion: Completion = .pending
    nonisolated(unsafe) private var continuation: CheckedContinuation<Value, Never>?
    nonisolated(unsafe) private var requestToken: RequestToken?
    nonisolated(unsafe) private var cancellationRequested = false

    nonisolated init(
        cancellationValue: Value,
        cancelRequest: @escaping @Sendable (RequestToken) -> Void
    ) {
        self.cancellationValue = cancellationValue
        self.cancelRequest = cancelRequest
    }

    nonisolated var shouldStartRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .pending = completion {
            return true
        }
        return false
    }

    nonisolated var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .finished = completion {
            return true
        }
        return false
    }

    nonisolated func install(_ continuation: CheckedContinuation<Value, Never>) {
        let completionToResume: Completion
        lock.lock()
        switch completion {
        case .pending:
            self.continuation = continuation
            completionToResume = .pending
        case .finished(let value):
            completionToResume = .finished(value)
        }
        lock.unlock()

        if case .finished(let value) = completionToResume {
            continuation.resume(returning: value)
        }
    }

    nonisolated func register(requestToken: RequestToken) {
        lock.lock()
        self.requestToken = requestToken
        let shouldCancel = cancellationRequested
        lock.unlock()

        if shouldCancel {
            cancelRequest(requestToken)
        }
    }

    nonisolated func finish(returning value: Value) {
        let continuationToResume: CheckedContinuation<Value, Never>?
        lock.lock()
        guard case .pending = completion else {
            lock.unlock()
            return
        }
        completion = .finished(value)
        continuationToResume = continuation
        continuation = nil
        lock.unlock()

        continuationToResume?.resume(returning: value)
    }

    nonisolated func cancel() {
        let requestTokenToCancel: RequestToken?
        let continuationToResume: CheckedContinuation<Value, Never>?
        lock.lock()
        guard case .pending = completion else {
            lock.unlock()
            return
        }
        cancellationRequested = true
        completion = .finished(cancellationValue)
        requestTokenToCancel = requestToken
        continuationToResume = continuation
        continuation = nil
        lock.unlock()

        if let requestTokenToCancel {
            cancelRequest(requestTokenToCancel)
        }
        continuationToResume?.resume(returning: cancellationValue)
    }
}

private final class PhotoResourceDataRequestState: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var requestID: PHAssetResourceDataRequestID?
    nonisolated(unsafe) private var cancellationRequested = false
    nonisolated(unsafe) private var writeError: Error?

    nonisolated init() { }

    nonisolated var shouldStartRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !cancellationRequested
    }

    nonisolated var shouldAcceptData: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !cancellationRequested && writeError == nil
    }

    nonisolated func register(requestID: PHAssetResourceDataRequestID) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = cancellationRequested || writeError != nil
        lock.unlock()

        if shouldCancel {
            PHAssetResourceManager.default().cancelDataRequest(requestID)
        }
    }

    nonisolated func recordWriteError(_ error: Error) {
        let requestIDToCancel: PHAssetResourceDataRequestID?
        lock.lock()
        if writeError == nil {
            writeError = error
        }
        requestIDToCancel = requestID
        lock.unlock()

        if let requestIDToCancel {
            PHAssetResourceManager.default().cancelDataRequest(requestIDToCancel)
        }
    }

    nonisolated func cancel() {
        let requestIDToCancel: PHAssetResourceDataRequestID?
        lock.lock()
        cancellationRequested = true
        requestIDToCancel = requestID
        lock.unlock()

        if let requestIDToCancel {
            PHAssetResourceManager.default().cancelDataRequest(requestIDToCancel)
        }
    }

    nonisolated func result(frameworkError: Error?, closeError: Error?) -> Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }
        if cancellationRequested {
            return .failure(CancellationError())
        }
        if let writeError {
            return .failure(writeError)
        }
        if let closeError {
            return .failure(closeError)
        }
        if let frameworkError {
            return .failure(frameworkError)
        }
        return .success(())
    }
}

private enum PhotoResourceFileWriter {
    nonisolated static func write(
        resource: PHAssetResource,
        allowNetwork: Bool,
        directoryName: String,
        fileName: String
    ) async throws -> URL {
        let destinationURL = try makeDestinationURL(directoryName: directoryName, fileName: fileName)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork

        do {
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let fileHandle = try FileHandle(forWritingTo: destinationURL)
            let state = PhotoResourceDataRequestState()

            let result: Result<Void, Error> = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard state.shouldStartRequest else {
                        try? fileHandle.close()
                        continuation.resume(returning: .failure(CancellationError()))
                        return
                    }

                    let requestID = PHAssetResourceManager.default().requestData(
                        for: resource,
                        options: options,
                        dataReceivedHandler: { data in
                            guard state.shouldAcceptData else {
                                return
                            }
                            do {
                                try fileHandle.write(contentsOf: data)
                            } catch {
                                state.recordWriteError(error)
                            }
                        },
                        completionHandler: { error in
                            let closeError: Error?
                            do {
                                try fileHandle.close()
                                closeError = nil
                            } catch {
                                closeError = error
                            }
                            continuation.resume(returning: state.result(frameworkError: error, closeError: closeError))
                        }
                    )
                    state.register(requestID: requestID)
                }
            } onCancel: {
                state.cancel()
            }

            try result.get()
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    nonisolated static func copyToTemporaryFile(
        sourceURL: URL,
        directoryName: String,
        fileName: String
    ) throws -> URL {
        let destinationURL = try makeDestinationURL(directoryName: directoryName, fileName: fileName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    nonisolated private static func makeDestinationURL(directoryName: String, fileName: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let safeFileName = URL(fileURLWithPath: fileName).lastPathComponent
        let resolvedFileName = safeFileName.isEmpty ? "Photo" : safeFileName
        return directoryURL.appending(path: "\(UUID().uuidString)-\(resolvedFileName)")
    }
}

#if os(iOS)
enum PhotosPickerPhotoImporter {
    enum ImportPhase {
        case reading
        case downloadingOriginal(progress: Double?)
    }

    enum ImportError: LocalizedError {
        case originalResourceUnavailable
        case unreadableImage
        case transferableReadFailed

        nonisolated var errorDescription: String? {
            switch self {
            case .originalResourceUnavailable:
                return AppLocalization.string("manualPicker.originalResourceUnavailable")
            case .unreadableImage:
                return AppLocalization.string("manualPicker.noReadableImages")
            case .transferableReadFailed:
                return AppLocalization.string("manualPicker.transferableReadFailed")
            }
        }
    }

    private struct PickedPhotoFile: Transferable {
        let fileURL: URL?
        let data: Data?
        let suggestedFileName: String?

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .image) { receivedFile in
                let fileName = receivedFile.file.lastPathComponent
                return PickedPhotoFile(
                    fileURL: try PhotoResourceFileWriter.copyToTemporaryFile(
                        sourceURL: receivedFile.file,
                        directoryName: PhotoTemporaryFileStore.importsDirectoryName,
                        fileName: fileName
                    ),
                    data: nil,
                    suggestedFileName: fileName
                )
            }
            DataRepresentation(importedContentType: .image) { data in
                PickedPhotoFile(fileURL: nil, data: data, suggestedFileName: nil)
            }
        }
    }

    nonisolated static func importAsset(
        from item: PhotosPickerItem,
        index: Int,
        progressHandler: @MainActor @escaping (ImportPhase) -> Void = { _ in }
    ) async throws -> PhotoAsset {
        try Task.checkCancellation()
        let id = item.itemIdentifier ?? UUID().uuidString
        var importFailure: ImportError?

        await progressHandler(.downloadingOriginal(progress: nil))
        do {
            if let asset = try await importOriginalResource(from: item, id: id) {
                return asset
            }
        } catch let error as ImportError {
            importFailure = error
        }

        try Task.checkCancellation()
        await progressHandler(.reading)
        do {
            if let pickedFile = try await item.loadTransferable(type: PickedPhotoFile.self) {
                let fileName = pickedFile.suggestedFileName ?? suggestedFileName(for: item, index: index)
                if let fileURL = pickedFile.fileURL {
                    if let asset = PhotoFileImporter.importAsset(from: fileURL, id: id, suggestedFileName: fileName) {
                        return asset
                    }
                    PhotoTemporaryFileStore.removeIfManaged(fileURL)
                }
                if let data = pickedFile.data,
                   let asset = PhotoFileImporter.importAsset(from: data, suggestedFileName: fileName, id: id) {
                    return asset
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            importFailure = importFailure ?? .transferableReadFailed
        }

        try Task.checkCancellation()
        do {
            if let asset = try await importLegacyTransferableData(
                from: item,
                id: id,
                index: index,
                progressHandler: progressHandler
            ) {
                return asset
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            importFailure = importFailure ?? .transferableReadFailed
        }

        throw importFailure ?? ImportError.unreadableImage
    }

    private nonisolated static func importLegacyTransferableData(
        from item: PhotosPickerItem,
        id: String,
        index: Int,
        progressHandler: @MainActor @escaping (ImportPhase) -> Void
    ) async throws -> PhotoAsset? {
        guard let data = try await legacyTransferableData(from: item, progressHandler: progressHandler) else {
            return nil
        }

        return PhotoFileImporter.importAsset(
            from: data,
            suggestedFileName: suggestedFileName(for: item, index: index),
            id: id
        )
    }

    private nonisolated static func legacyTransferableData(
        from item: PhotosPickerItem,
        progressHandler: @MainActor @escaping (ImportPhase) -> Void
    ) async throws -> Data? {
        let state = CancellablePhotoRequestState<Result<Data?, Error>, Progress>(
            cancellationValue: .failure(CancellationError()),
            cancelRequest: { $0.cancel() }
        )

        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                guard state.shouldStartRequest else {
                    return
                }

                let progress = item.loadTransferable(type: Data.self) { result in
                    switch result {
                    case .success(let data):
                        state.finish(returning: .success(data))
                    case .failure(let error):
                        state.finish(returning: .failure(error))
                    }
                }
                state.register(requestToken: progress)

                Task {
                    try? await Task.sleep(for: .milliseconds(350))

                    while !Task.isCancelled && !state.isFinished && !progress.isFinished {
                        let fraction = normalizedFractionCompleted(for: progress)
                        await progressHandler(.downloadingOriginal(progress: fraction))
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
            }
        } onCancel: {
            state.cancel()
        }

        return try result.get()
    }

    private nonisolated static func normalizedFractionCompleted(for progress: Progress) -> Double? {
        guard progress.totalUnitCount > 0 else {
            return nil
        }

        let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
        return min(max(fraction, 0), 1)
    }

    private nonisolated static func importOriginalResource(from item: PhotosPickerItem, id: String) async throws -> PhotoAsset? {
        guard let itemIdentifier = item.itemIdentifier else {
            return nil
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [itemIdentifier], options: nil)
        guard let photoLibraryAsset = fetchResult.firstObject,
              let resource = preferredOriginalResource(for: photoLibraryAsset) else {
            return nil
        }

        do {
            let fileURL = try await PhotoResourceFileWriter.write(
                resource: resource,
                allowNetwork: true,
                directoryName: PhotoTemporaryFileStore.importsDirectoryName,
                fileName: resource.originalFilename
            )
            guard let asset = PhotoFileImporter.importAsset(
                from: fileURL,
                id: id,
                suggestedFileName: resource.originalFilename
            ) else {
                try? FileManager.default.removeItem(at: fileURL)
                throw ImportError.unreadableImage
            }
            return asset
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImportError.originalResourceUnavailable
        }
    }

    private nonisolated static func preferredOriginalResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        if let rawResource = resources.first(where: isRawResource) {
            return rawResource
        }

        let preferredTypes: [PHAssetResourceType] = [.fullSizePhoto, .photo, .alternatePhoto]
        for type in preferredTypes {
            if let resource = resources.first(where: { $0.type == type }) {
                return resource
            }
        }

        return resources.first
    }

    private nonisolated static func isRawResource(_ resource: PHAssetResource) -> Bool {
        guard let type = UTType(resource.uniformTypeIdentifier) else {
            return false
        }

        let rawImageType = UTType("public.camera-raw-image")
        return rawImageType.map { type.conforms(to: $0) } ?? false
    }

    private nonisolated static func suggestedFileName(for item: PhotosPickerItem, index: Int) -> String {
        let baseFileName = "\(AppLocalization.string("photoFileImporter.pickedImage")) \(index + 1)"
        return item.supportedContentTypes.first?.preferredFilenameExtension.map {
            "\(baseFileName).\($0)"
        } ?? baseFileName
    }
}
#endif

enum PhotoLoader {
    static func thumbnail(for asset: PhotoAsset, size: CGSize) async -> PlatformImage? {
        switch asset.source {
        case .photoLibrary(let photoLibraryAsset):
            return await thumbnail(for: photoLibraryAsset, size: size)
        case .file(let file):
            return thumbnail(from: file, maxPixelLength: max(size.width, size.height))
        }
    }

    static func previewImage(for asset: PhotoAsset, size: CGSize) async -> PlatformImage? {
        switch asset.source {
        case .photoLibrary(let photoLibraryAsset):
            return await previewImage(for: photoLibraryAsset, size: size)
        case .file(let file):
            return thumbnail(from: file, maxPixelLength: max(size.width, size.height))
        }
    }

    static func metadata(for asset: PhotoAsset, allowNetwork: Bool) async -> PhotoDetailState {
        switch asset.source {
        case .photoLibrary(let photoLibraryAsset):
            return await metadata(for: photoLibraryAsset, allowNetwork: allowNetwork)
        case .file(let file):
            if FileManager.default.fileExists(atPath: file.fileURL.path) {
                return .loaded(MetadataParser.parse(url: file.fileURL, fallbackLocation: nil))
            }
            guard let data = file.data else {
                return .failed(AppLocalization.string("photoLoader.missingReadableResource"))
            }
            return .loaded(MetadataParser.parse(data: data, fallbackLocation: nil))
        }
    }

    static func shareablePhotoURL(for asset: PhotoAsset, allowNetwork: Bool) async throws -> URL {
        switch asset.source {
        case .photoLibrary(let photoLibraryAsset):
            guard let resource = imageResource(for: photoLibraryAsset) else {
                throw PhotoLoaderError.missingPhotoResource
            }

            return try await PhotoResourceFileWriter.write(
                resource: resource,
                allowNetwork: allowNetwork,
                directoryName: PhotoTemporaryFileStore.shareDirectoryName,
                fileName: sanitizedFileName(
                    resource.originalFilename,
                    uniformTypeIdentifier: resource.uniformTypeIdentifier
                )
            )
        case .file(let file):
            if FileManager.default.fileExists(atPath: file.fileURL.path) {
                return file.fileURL
            }

            guard let data = file.data else {
                throw PhotoLoaderError.missingPhotoResource
            }
            return try temporaryShareFileURL(
                fileName: file.fileName,
                data: data,
                uniformTypeIdentifier: nil
            )
        }
    }

    static func locallyAvailableAssetIDs(from assets: [PhotoAsset]) async -> Set<String> {
        let libraryAssets = assets.compactMap(\.photoLibraryAsset)
        guard !libraryAssets.isEmpty else {
            return Set(assets.map(\.id))
        }

        var availableIDs = Set<String>()
        let batchSize = 12
        var batchStart = 0

        while batchStart < libraryAssets.count {
            guard !Task.isCancelled else {
                return availableIDs
            }
            let batch = Array(libraryAssets[batchStart ..< min(batchStart + batchSize, libraryAssets.count)])

            let batchResults = await withTaskGroup(of: String?.self) { group in
                for asset in batch {
                    group.addTask {
                        let isLocal = await hasLocalOriginalData(for: asset)
                        return isLocal ? asset.localIdentifier : nil
                    }
                }

                var identifiers: [String] = []
                for await identifier in group {
                    if let identifier {
                        identifiers.append(identifier)
                    }
                }
                return identifiers
            }

            availableIDs.formUnion(batchResults)
            batchStart += batchSize
        }

        return availableIDs
    }

    private static func thumbnail(for asset: PHAsset, size: CGSize) async -> PlatformImage? {
        await requestImage(for: asset, size: size, contentMode: .aspectFill)
    }

    private static func previewImage(for asset: PHAsset, size: CGSize) async -> PlatformImage? {
        await requestImage(for: asset, size: size, contentMode: .aspectFit)
    }

    private static func requestImage(for asset: PHAsset, size: CGSize, contentMode: PHImageContentMode) async -> PlatformImage? {
        let state = CancellablePhotoRequestState<PlatformImage?, PHImageRequestID>(
            cancellationValue: nil,
            cancelRequest: { PHImageManager.default().cancelImageRequest($0) }
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                guard state.shouldStartRequest else {
                    return
                }

                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = contentMode == .aspectFit ? .fast : .exact
                options.isNetworkAccessAllowed = false

                let requestID = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: size,
                    contentMode: contentMode,
                    options: options
                ) { image, info in
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                    guard !isDegraded else {
                        return
                    }
                    state.finish(returning: image)
                }
                state.register(requestToken: requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func metadata(for asset: PHAsset, allowNetwork: Bool) async -> PhotoDetailState {
        if let resource = imageResource(for: asset) {
            do {
                let fileURL = try await PhotoResourceFileWriter.write(
                    resource: resource,
                    allowNetwork: allowNetwork,
                    directoryName: PhotoTemporaryFileStore.metadataDirectoryName,
                    fileName: resource.originalFilename
                )
                defer { try? FileManager.default.removeItem(at: fileURL) }
                return .loaded(MetadataParser.parse(url: fileURL, fallbackLocation: asset.location))
            } catch {
                if error is CancellationError || Task.isCancelled {
                    return .failed(CancellationError().localizedDescription)
                }
                if let fallback = await imageManagerData(for: asset, allowNetwork: allowNetwork) {
                    return .loaded(MetadataParser.parse(data: fallback, fallbackLocation: asset.location))
                }

                if !allowNetwork {
                    return .needsDownload(AppLocalization.string("photoLoader.needsDownload"))
                }

                return .failed(error.localizedDescription)
            }
        }

        if let data = await imageManagerData(for: asset, allowNetwork: allowNetwork) {
            return .loaded(MetadataParser.parse(data: data, fallbackLocation: asset.location))
        }

        if Task.isCancelled {
            return .failed(CancellationError().localizedDescription)
        }
        if !allowNetwork {
            return .needsDownload(AppLocalization.string("photoLoader.needsDownload"))
        }

        return .failed(AppLocalization.string("photoLoader.missingReadableResource"))
    }

    private static func thumbnail(from file: LocalPhotoFile, maxPixelLength: CGFloat) -> PlatformImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(ceil(maxPixelLength)))
        ]

        let source: CGImageSource?
        if FileManager.default.fileExists(atPath: file.fileURL.path) {
            source = CGImageSourceCreateWithURL(file.fileURL as CFURL, nil)
        } else if let data = file.data {
            source = CGImageSourceCreateWithData(data as CFData, nil)
        } else {
            source = nil
        }

        guard let source,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
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

    private static func imageManagerData(for asset: PHAsset, allowNetwork: Bool) async -> Data? {
        let state = CancellablePhotoRequestState<Data?, PHImageRequestID>(
            cancellationValue: nil,
            cancelRequest: { PHImageManager.default().cancelImageRequest($0) }
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                guard state.shouldStartRequest else {
                    return
                }

                let options = PHImageRequestOptions()
                options.version = .current
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = allowNetwork

                let requestID = PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, info in
                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) == true
                    state.finish(returning: !allowNetwork && isInCloud ? nil : data)
                }
                state.register(requestToken: requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func hasLocalOriginalData(for asset: PHAsset) async -> Bool {
        guard let resource = imageResource(for: asset) else {
            return false
        }

        let state = CancellablePhotoRequestState<Bool, PHAssetResourceDataRequestID>(
            cancellationValue: false,
            cancelRequest: { PHAssetResourceManager.default().cancelDataRequest($0) }
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                guard state.shouldStartRequest else {
                    return
                }

                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = false
                let requestID = PHAssetResourceManager.default().requestData(
                    for: resource,
                    options: options,
                    dataReceivedHandler: { _ in },
                    completionHandler: { error in
                        state.finish(returning: error == nil)
                    }
                )
                state.register(requestToken: requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func temporaryShareFileURL(fileName: String, data: Data, uniformTypeIdentifier: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ExifTool-Share", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeFileName = sanitizedFileName(fileName, uniformTypeIdentifier: uniformTypeIdentifier)
        let url = directory.appending(path: "\(UUID().uuidString)-\(safeFileName)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func sanitizedFileName(_ fileName: String, uniformTypeIdentifier: String?) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:")
        let sanitizedBaseName = fileName
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var result = sanitizedBaseName.isEmpty ? "Photo" : sanitizedBaseName
        if !result.contains("."),
           let uniformTypeIdentifier,
           let preferredExtension = UTType(uniformTypeIdentifier)?.preferredFilenameExtension {
            result += ".\(preferredExtension)"
        }

        return result
    }
}

enum PhotoLoaderError: LocalizedError {
    case missingPhotoResource

    var errorDescription: String? {
        switch self {
        case .missingPhotoResource:
            return AppLocalization.string("photoLoader.missingShareableResource")
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

#endif
