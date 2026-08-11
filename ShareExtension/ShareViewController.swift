//
//  ShareViewController.swift
//  ExifToolShareExtension
//
//  Created by Codex on 2026/4/17.
//

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
        static let urlScheme = "exiftool"
        static let urlHost = "shared-photo"
        static let fileQueryItemName = "file"
    }

    private enum LocalizedText {
        static let importFailed = String(localized: "shareExtension.importFailed")
        static let openFailed = String(localized: "shareExtension.openFailed")
        static let openInApp = String(localized: "shareExtension.openInApp")
        static let openingApp = String(localized: "shareExtension.openingApp")
        static let photoReady = String(localized: "shareExtension.photoReady")
        static let readingPhoto = String(localized: "shareExtension.readingPhoto")
    }

    private var didStartProcessing = false
    private var didAttemptToOpenApp = false
    private var pendingContainingAppURL: URL?
    private let progressView = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private let openButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        cleanupStaleSharedFiles()

        view.backgroundColor = .systemBackground

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.startAnimating()

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = LocalizedText.readingPhoto
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.setTitle(LocalizedText.openInApp, for: .normal)
        openButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(openButtonTapped), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [progressView, statusLabel, openButton])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didStartProcessing else {
            return
        }

        didStartProcessing = true
        importSharedImage()
    }

    private func importSharedImage() {
        guard let provider = firstImageItemProvider() else {
            finish()
            return
        }

        let typeIdentifier = preferredImageTypeIdentifier(from: provider)
        let sendableProvider = SendableItemProvider(provider)

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self, sendableProvider] url, _ in
            if let url,
               let destinationFileName = Self.copySharedFile(from: url, preferredExtension: UTType(typeIdentifier)?.preferredFilenameExtension) {
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    self.prepareToOpenContainingApp(with: destinationFileName)
                }
                return
            }

            sendableProvider.value.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
                let destinationFileName = data.flatMap {
                    Self.writeSharedImageData($0, preferredExtension: UTType(typeIdentifier)?.preferredFilenameExtension)
                }

                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    if let destinationFileName {
                        self.prepareToOpenContainingApp(with: destinationFileName)
                    } else {
                        self.showImportFailure()
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
        let registeredTypes = provider.registeredTypeIdentifiers
        return registeredTypes.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
    }

    nonisolated private static func copySharedFile(from sourceURL: URL, preferredExtension: String?) -> String? {
        let destinationFileName = sharedFileName(fileExtension: sourceURL.pathExtension.isEmpty ? preferredExtension : sourceURL.pathExtension)

        guard let destinationURL = destinationURL(for: destinationFileName) else {
            return nil
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationFileName
        } catch {
            return nil
        }
    }

    nonisolated private static func writeSharedImageData(_ data: Data, preferredExtension: String?) -> String? {
        let destinationFileName = sharedFileName(fileExtension: preferredExtension)

        guard let destinationURL = destinationURL(for: destinationFileName) else {
            return nil
        }

        do {
            try data.write(to: destinationURL, options: .atomic)
            return destinationFileName
        } catch {
            return nil
        }
    }

    nonisolated private static func destinationURL(for fileName: String) -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier) else {
            return nil
        }

        let directoryURL = containerURL.appending(path: Constants.sharedDirectoryName, directoryHint: .isDirectory)

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
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier) else {
            return
        }

        let directoryURL = containerURL.appending(path: Constants.sharedDirectoryName, directoryHint: .isDirectory)
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoffDate = Date().addingTimeInterval(-maximumAge)
        for fileURL in fileURLs {
            let modificationDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modificationDate.map({ $0 < cutoffDate }) ?? true {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func prepareToOpenContainingApp(with fileName: String) {
        var components = URLComponents()
        components.scheme = Constants.urlScheme
        components.host = Constants.urlHost
        components.queryItems = [
            URLQueryItem(name: Constants.fileQueryItemName, value: fileName)
        ]

        guard let url = components.url else {
            showImportFailure()
            return
        }

        DispatchQueue.main.async {
            self.pendingContainingAppURL = url
            self.progressView.stopAnimating()
            self.progressView.isHidden = true
            self.statusLabel.text = LocalizedText.photoReady
            self.openButton.isHidden = false
        }
    }

    @objc private func openButtonTapped() {
        guard let pendingContainingAppURL else {
            showImportFailure()
            return
        }

        openContainingAppURL(pendingContainingAppURL)
    }

    private func openContainingAppURL(_ url: URL) {
        guard !didAttemptToOpenApp else {
            return
        }

        guard let extensionContext else {
            showOpenFailure()
            return
        }

        didAttemptToOpenApp = true
        progressView.isHidden = false
        progressView.startAnimating()
        statusLabel.text = LocalizedText.openingApp
        openButton.isHidden = true

        extensionContext.open(url) { [weak self] didOpen in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                if didOpen {
                    self.finish()
                } else {
                    self.showOpenFailure()
                }
            }
        }
    }

    private func showImportFailure() {
        DispatchQueue.main.async {
            self.progressView.stopAnimating()
            self.progressView.isHidden = true
            self.statusLabel.text = LocalizedText.importFailed
            self.openButton.isHidden = true
        }
    }

    private func showOpenFailure() {
        DispatchQueue.main.async {
            self.didAttemptToOpenApp = false
            self.progressView.stopAnimating()
            self.progressView.isHidden = true
            self.statusLabel.text = LocalizedText.openFailed
            self.openButton.isHidden = false
        }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
