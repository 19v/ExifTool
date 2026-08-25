import ImageIO
import Observation
import SwiftUI
import UIKit

private struct ShareExtensionProcessingResult: @unchecked Sendable {
    let metadata: PhotoMetadata
    let previewImage: CGImage?
}

@MainActor
@Observable
final class ShareExtensionModel {
    enum Phase: Equatable {
        case reading
        case loaded
        case failed(String)
    }

    private(set) var phase = Phase.reading
    private(set) var metadata: PhotoMetadata?
    private(set) var previewImage: UIImage?
    private(set) var displayName = ""

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var fileURL: URL?

    var isFinishedReading: Bool {
        phase != .reading
    }

    func load(fileURL: URL, displayName: String) {
        cancelLoading()
        self.fileURL = fileURL
        self.displayName = Self.safeDisplayName(displayName, fallbackURL: fileURL)
        metadata = nil
        previewImage = nil
        phase = .reading

        loadTask = Task { [weak self] in
            let result = await MediaProcessing.run {
                ShareExtensionProcessingResult(
                    metadata: MetadataParser.parse(url: fileURL, fallbackCoordinate: nil),
                    previewImage: ImageThumbnailDecoder.decode(
                        fileURL: fileURL,
                        data: nil,
                        maxPixelLength: 1_600
                    )
                )
            }

            guard let self, !Task.isCancelled, self.fileURL == fileURL else {
                return
            }

            guard result.previewImage != nil || !result.metadata.sections.isEmpty else {
                phase = .failed(String(localized: "shareExtension.importFailed"))
                return
            }

            metadata = result.metadata
            previewImage = result.previewImage.map(UIImage.init(cgImage:))
            phase = .loaded
        }
    }

    func retry() {
        guard let fileURL else {
            showImportFailure()
            return
        }
        load(fileURL: fileURL, displayName: displayName)
    }

    func showImportFailure() {
        cancelLoading()
        phase = .failed(String(localized: "shareExtension.importFailed"))
    }

    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    private static func safeDisplayName(_ displayName: String, fallbackURL: URL) -> String {
        let safeName = URL(fileURLWithPath: displayName).lastPathComponent
        return safeName.isEmpty ? fallbackURL.lastPathComponent : safeName
    }
}

struct ShareExtensionView: View {
    @Bindable var model: ShareExtensionModel
    let onCancel: () -> Void
    let onDone: () -> Void

    @State private var showsChineseKeys = MetadataLanguagePreference.defaultShowsChineseKeys

    var body: some View {
        NavigationStack {
            ShareExtensionContent(
                phase: model.phase,
                previewImage: model.previewImage,
                displayName: model.displayName,
                metadata: model.metadata,
                showsChineseKeys: showsChineseKeys,
                onRetry: model.retry
            )
            .navigationTitle("shareExtension.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("shareExtension.cancel", systemImage: "xmark", action: onCancel)
                        .labelStyle(.iconOnly)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("shareExtension.done", systemImage: "checkmark", action: onDone)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(!model.isFinishedReading)
                }

                if model.metadata != nil {
                    ToolbarItemGroup(placement: .bottomBar) {
                        metadataLanguageButton
                        Spacer()
                    }
                }
            }
        }
    }

    private var metadataLanguageButton: some View {
        Button {
            showsChineseKeys.toggle()
        } label: {
            Label("shareExtension.metadataLanguage", systemImage: "character.bubble")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("shareExtension.metadataLanguage")
        .accessibilityValue(
            showsChineseKeys
                ? String(localized: "shareExtension.language.chinese")
                : String(localized: "shareExtension.language.english")
        )
        .sensoryFeedback(.selection, trigger: showsChineseKeys)
    }
}

private struct ShareExtensionContent: View {
    let phase: ShareExtensionModel.Phase
    let previewImage: UIImage?
    let displayName: String
    let metadata: PhotoMetadata?
    let showsChineseKeys: Bool
    let onRetry: () -> Void

    var body: some View {
        switch phase {
        case .reading:
            ShareExtensionLoadingView()
        case .loaded:
            if let metadata {
                ShareExtensionMetadataList(
                    previewImage: previewImage,
                    displayName: displayName,
                    metadata: metadata,
                    showsChineseKeys: showsChineseKeys
                )
            } else {
                ShareExtensionFailureView(
                    message: String(localized: "shareExtension.importFailed"),
                    onRetry: onRetry
                )
            }
        case .failed(let message):
            ShareExtensionFailureView(message: message, onRetry: onRetry)
        }
    }
}

private struct ShareExtensionLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("shareExtension.readingExif")
                .font(.headline)
            Text("shareExtension.readingExif.detail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShareExtensionFailureView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("shareExtension.failedTitle", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("shareExtension.retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct ShareExtensionMetadataList: View {
    let previewImage: UIImage?
    let displayName: String
    private let projection: MetadataDisplayProjection

    init(
        previewImage: UIImage?,
        displayName: String,
        metadata: PhotoMetadata,
        showsChineseKeys: Bool
    ) {
        self.previewImage = previewImage
        self.displayName = displayName
        projection = MetadataDisplayProjection(
            metadata: metadata,
            showsChineseKeys: showsChineseKeys
        )
    }

    var body: some View {
        List {
            Section {
                ShareExtensionPhotoPreview(image: previewImage)

                LabeledContent("shareExtension.fileName") {
                    Text(displayName)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }

            if projection.listSections.isEmpty {
                ContentUnavailableView(
                    "shareExtension.noExif",
                    systemImage: "info.circle",
                    description: Text("shareExtension.noExif.detail")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(projection.listSections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            ShareExtensionMetadataRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

private struct ShareExtensionPhotoPreview: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(image.size, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 300)
                .compositingGroup()
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityLabel("shareExtension.photoPreview")
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityLabel("shareExtension.previewUnavailable")
        }
    }
}

private struct ShareExtensionMetadataRow: View {
    let item: MetadataDisplayItem

    var body: some View {
        LabeledContent {
            Text(item.value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(item.title)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum MetadataLanguagePreference {
    static var defaultShowsChineseKeys: Bool {
        guard let preferredLanguage = Locale.preferredLanguages.first else {
            return false
        }

        return Locale(identifier: preferredLanguage).language.languageCode?.identifier == "zh"
    }
}
