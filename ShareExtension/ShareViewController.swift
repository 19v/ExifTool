//
//  ShareViewController.swift
//  ExifToolShareExtension
//
//  Created by Codex on 2026/4/17.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

private final class SendableItemProvider: @unchecked Sendable {
    nonisolated(unsafe) let value: NSItemProvider

    nonisolated init(_ value: NSItemProvider) {
        self.value = value
    }
}

final class ShareViewController: UIViewController {
    private enum Constants {
        nonisolated static let appGroupIdentifier = "group.com.echopie.ExifTool"
        nonisolated static let sharedDirectoryName = "SharedPhotos"
    }

    private let model = ShareExtensionModel()
    private var didStartProcessing = false
    private var sharedFileURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()

        cleanupStaleSharedFiles()
        installContentView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didStartProcessing else {
            return
        }

        didStartProcessing = true
        importSharedImage()
    }

    private func installContentView() {
        let contentView = ShareExtensionView(
            model: model,
            onCancel: { [weak self] in
                self?.finish()
            },
            onDone: { [weak self] in
                self?.finish()
            }
        )
        let hostingController = UIHostingController(rootView: contentView)

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func importSharedImage() {
        guard let provider = firstImageItemProvider() else {
            model.showImportFailure()
            return
        }

        let typeIdentifier = preferredImageTypeIdentifier(from: provider)
        let preferredExtension = UTType(typeIdentifier)?.preferredFilenameExtension
        let suggestedFileName = provider.suggestedName
        let sendableProvider = SendableItemProvider(provider)

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
            if let url,
               let destinationURL = Self.copySharedFile(
                   from: url,
                   preferredExtension: preferredExtension
               ) {
                Task { @MainActor [weak self] in
                    self?.presentSharedImage(
                        at: destinationURL,
                        displayName: suggestedFileName ?? url.lastPathComponent
                    )
                }
                return
            }

            sendableProvider.value.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
                let destinationURL = data.flatMap {
                    Self.writeSharedImageData($0, preferredExtension: preferredExtension)
                }

                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    if let destinationURL {
                        self.presentSharedImage(
                            at: destinationURL,
                            displayName: suggestedFileName ?? destinationURL.lastPathComponent
                        )
                    } else {
                        self.model.showImportFailure()
                    }
                }
            }
        }
    }

    private func firstImageItemProvider() -> NSItemProvider? {
        extensionContext?
            .inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
    }

    private func preferredImageTypeIdentifier(from provider: NSItemProvider) -> String {
        provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
    }

    private func presentSharedImage(at fileURL: URL, displayName: String) {
        sharedFileURL = fileURL
        model.load(fileURL: fileURL, displayName: displayName)
    }

    nonisolated private static func copySharedFile(
        from sourceURL: URL,
        preferredExtension: String?
    ) -> URL? {
        let destinationFileName = sharedFileName(
            fileExtension: sourceURL.pathExtension.isEmpty ? preferredExtension : sourceURL.pathExtension
        )

        guard let destinationURL = destinationURL(for: destinationFileName) else {
            return nil
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    nonisolated private static func writeSharedImageData(
        _ data: Data,
        preferredExtension: String?
    ) -> URL? {
        let destinationFileName = sharedFileName(fileExtension: preferredExtension)

        guard let destinationURL = destinationURL(for: destinationFileName) else {
            return nil
        }

        do {
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            return nil
        }
    }

    nonisolated private static func destinationURL(for fileName: String) -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier
        ) else {
            return nil
        }

        let directoryURL = containerURL.appending(
            path: Constants.sharedDirectoryName,
            directoryHint: .isDirectory
        )

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return directoryURL.appending(path: fileName)
        } catch {
            return nil
        }
    }

    nonisolated private static func sharedFileName(fileExtension: String?) -> String {
        let suffix = fileExtension.flatMap { $0.isEmpty ? nil : $0 } ?? "jpg"
        return "\(UUID().uuidString).\(suffix)"
    }

    private func cleanupStaleSharedFiles(olderThan maximumAge: TimeInterval = 24 * 60 * 60) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier
        ) else {
            return
        }

        let directoryURL = containerURL.appending(
            path: Constants.sharedDirectoryName,
            directoryHint: .isDirectory
        )
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-maximumAge)
        for fileURL in fileURLs {
            let modificationDate = try? fileURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if modificationDate.map({ $0 < cutoffDate }) ?? true {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func finish() {
        model.cancelLoading()
        if let sharedFileURL {
            try? FileManager.default.removeItem(at: sharedFileURL)
            self.sharedFileURL = nil
        }
        extensionContext?.completeRequest(returningItems: nil)
    }
}
