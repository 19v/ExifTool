//
//  MediaProcessing.swift
//  ExifTool
//
//  Runs synchronous ImageIO and metadata work away from the main actor.
//

import CoreGraphics
import Foundation
import ImageIO

nonisolated enum MediaProcessing {
    static func run<Value: Sendable>(
        priority: TaskPriority = .userInitiated,
        operation: @escaping @Sendable () -> Value
    ) async -> Value {
        let task = Task.detached(priority: priority, operation: operation)

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

nonisolated enum ImageThumbnailDecoder {
    static func decode(
        fileURL: URL,
        data: Data?,
        maxPixelLength: CGFloat
    ) -> CGImage? {
        guard !Task.isCancelled else {
            return nil
        }

        let source: CGImageSource?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            source = CGImageSourceCreateWithURL(fileURL as CFURL, nil)
        } else if let data {
            source = CGImageSourceCreateWithData(data as CFData, nil)
        } else {
            source = nil
        }

        guard !Task.isCancelled, let source else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(ceil(maxPixelLength)))
        ]
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        return Task.isCancelled ? nil : image
    }
}
