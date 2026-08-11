//
//  ShareViewController.swift
//  ExifToolShareExtension
//
//  Created by Codex on 2026/4/17.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private enum Constants {
        static let appGroupIdentifier = "group.com.echopie.ExifTool"
        static let sharedDirectoryName = "SharedPhotos"
        static let urlScheme = "exiftool"
        static let urlHost = "shared-photo"
        static let fileQueryItemName = "file"
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
        statusLabel.text = "正在读取照片"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.setTitle("在 ExifTool 中查看", for: .normal)
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

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
            guard let self else {
                return
            }

            if let url,
               let destinationFileName = self.copySharedFile(from: url, preferredExtension: UTType(typeIdentifier)?.preferredFilenameExtension) {
                self.prepareToOpenContainingApp(with: destinationFileName)
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] data, _ in
                guard let self else {
                    return
                }

                if let data,
                   let destinationFileName = self.writeSharedImageData(data, preferredExtension: UTType(typeIdentifier)?.preferredFilenameExtension) {
                    self.prepareToOpenContainingApp(with: destinationFileName)
                } else {
                    self.showImportFailure()
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

    private func copySharedFile(from sourceURL: URL, preferredExtension: String?) -> String? {
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

    private func writeSharedImageData(_ data: Data, preferredExtension: String?) -> String? {
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

    private func destinationURL(for fileName: String) -> URL? {
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

    private func sharedFileName(fileExtension: String?) -> String {
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
            self.statusLabel.text = "照片已准备好"
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

        didAttemptToOpenApp = true

        openURLViaResponderChain(url)
        extensionContext?.open(url, completionHandler: nil)
        finishAfterOpeningApp()
    }

    private func showImportFailure() {
        DispatchQueue.main.async {
            self.progressView.stopAnimating()
            self.progressView.isHidden = true
            self.statusLabel.text = "无法打开这张照片"
            self.openButton.isHidden = true
        }
    }

    private func openURLViaResponderChain(_ url: URL) {
        let openURLSelector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if currentResponder.responds(to: openURLSelector) {
                currentResponder.perform(openURLSelector, with: url)
                return
            }

            responder = currentResponder.next
        }
    }

    private func finishAfterOpeningApp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.finish()
        }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
