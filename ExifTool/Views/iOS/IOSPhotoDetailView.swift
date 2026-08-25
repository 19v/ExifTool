#if os(iOS)

//
//  PhotoDetailView.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI
import UIKit

struct PhotoDetailView: View {
    let assets: [PhotoAsset]
    let sortOrder: PhotoAssetSortOrder

    @AppStorage("allowsICloudDownload") private var allowsICloudDownload = false
    @State private var currentAssetID: String
    @State private var showsChineseKeys: Bool
    @State private var modelStore = IOSPhotoDetailModelStore()

    init(
        assets: [PhotoAsset],
        initialAssetID: String,
        sortOrder: PhotoAssetSortOrder = .oldestFirst
    ) {
        self.assets = assets
        self.sortOrder = sortOrder
        let fallbackAsset = sortOrder == .oldestFirst ? assets.first : assets.last
        let resolvedInitialAssetID = assets.contains { $0.id == initialAssetID }
            ? initialAssetID
            : fallbackAsset?.id ?? initialAssetID
        _currentAssetID = State(initialValue: resolvedInitialAssetID)
        _showsChineseKeys = State(initialValue: MetadataLanguagePreference.defaultShowsChineseKeys)
    }

    var body: some View {
        if assets.isEmpty {
            ContentUnavailableView("没有可显示的照片", systemImage: "photo")
        } else {
            PhotoDetailPager(
                assets: assets,
                sortOrder: sortOrder,
                currentAssetID: $currentAssetID,
                showsChineseKeys: $showsChineseKeys,
                modelStore: modelStore
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .onAppear {
                ensureCurrentAssetExists()
            }
            .onChange(of: assets.map(\.id)) {
                ensureCurrentAssetExists()
                modelStore.removeModels(except: Set(assets.map(\.id)))
            }
            .navigationTitle(navigationTitle)
            .platformInlineNavigationTitle()
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                PhotoDetailPlatformToolbar(
                    showsChineseKeys: $showsChineseKeys,
                    photoNavigation: photoNavigation,
                    isPreparingPhotoShare: currentModel?.isPreparingPhotoShare ?? false,
                    canShareParameters: currentModel?.loadedMetadata != nil,
                    onSharePhoto: sharePhoto,
                    onShareParameters: shareParameters
                )
            }
            .platformTabBarHidden()
        }
    }

    private var navigationTitle: String {
        guard let currentIndex else {
            return ""
        }

        return "\(currentIndex + 1)/\(assets.count)"
    }

    private var currentAsset: PhotoAsset? {
        assets.first(where: { $0.id == currentAssetID })
    }

    private var currentModel: IOSPhotoDetailModel? {
        currentAsset.map { modelStore.model(for: $0.id) }
    }

    private var currentIndex: Int? {
        guard let currentAsset else {
            return nil
        }

        return orderedAssets.firstIndex(where: { $0.id == currentAsset.id })
    }

    private var photoNavigation: PhotoNavigationConfiguration? {
        guard assets.count > 1, let currentIndex else {
            return nil
        }

        return PhotoNavigationConfiguration(
            canSelectPrevious: currentIndex > 0,
            canSelectNext: currentIndex < assets.count - 1,
            selectPrevious: selectPreviousAsset,
            selectNext: selectNextAsset
        )
    }

    private func selectPreviousAsset() {
        guard let currentIndex, currentIndex > 0 else {
            return
        }

        selectAsset(orderedAssets[currentIndex - 1])
    }

    private func selectNextAsset() {
        guard let currentIndex, currentIndex < assets.count - 1 else {
            return
        }

        selectAsset(orderedAssets[currentIndex + 1])
    }

    private func ensureCurrentAssetExists() {
        guard let firstAsset = orderedAssets.first else {
            return
        }

        if currentAsset == nil {
            currentAssetID = firstAsset.id
        }
    }

    private func selectAsset(_ asset: PhotoAsset) {
        withAnimation {
            currentAssetID = asset.id
        }
    }

    private func sharePhoto() {
        guard let currentAsset, let currentModel else {
            return
        }

        Task {
            await currentModel.sharePhoto(
                asset: currentAsset,
                allowsICloudDownload: allowsICloudDownload
            )
        }
    }

    private func shareParameters() {
        guard let currentAsset, let currentModel else {
            return
        }

        currentModel.shareParameters(
            asset: currentAsset,
            showsChineseKeys: showsChineseKeys,
            visibleMetadataKeys: nil
        )
    }

    private var orderedAssets: OrderedPhotoAssets {
        OrderedPhotoAssets(assets: assets, sortOrder: sortOrder)
    }
}

private struct PhotoDetailPager: UIViewControllerRepresentable {
    let assets: [PhotoAsset]
    let sortOrder: PhotoAssetSortOrder
    @Binding var currentAssetID: String
    @Binding var showsChineseKeys: Bool
    let modelStore: IOSPhotoDetailModelStore

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PhotoDetailPageViewController {
        let pageViewController = PhotoDetailPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.view.backgroundColor = .clear

        if let initialIndex = orderedIndex(of: currentAssetID),
           let initialController = context.coordinator.controller(at: initialIndex) {
            pageViewController.setViewControllers(
                [initialController],
                direction: .forward,
                animated: false
            )
        }

        return pageViewController
    }

    func updateUIViewController(_ pageViewController: PhotoDetailPageViewController, context: Context) {
        context.coordinator.parent = self
        pageViewController.updateNavigationBarAppearanceIfVisible()

        guard !context.coordinator.isInteractiveTransition,
              let targetIndex = orderedIndex(of: currentAssetID),
              let targetController = context.coordinator.controller(at: targetIndex) else {
            return
        }

        guard let visibleController = pageViewController.viewControllers?.first,
              let visibleAssetID = context.coordinator.assetID(for: visibleController) else {
            pageViewController.setViewControllers(
                [targetController],
                direction: .forward,
                animated: false
            )
            return
        }

        guard visibleAssetID != currentAssetID else {
            return
        }

        let visibleIndex = orderedIndex(of: visibleAssetID) ?? targetIndex
        let direction: UIPageViewController.NavigationDirection = targetIndex >= visibleIndex
            ? .forward
            : .reverse
        pageViewController.setViewControllers(
            [targetController],
            direction: direction,
            animated: context.transaction.animation != nil
        )
    }

    func orderedIndex(of assetID: String) -> Int? {
        guard let sourceIndex = assets.firstIndex(where: { $0.id == assetID }) else {
            return nil
        }

        switch sortOrder {
        case .oldestFirst:
            return sourceIndex
        case .newestFirst:
            return assets.count - sourceIndex - 1
        }
    }

    func asset(at orderedIndex: Int) -> PhotoAsset? {
        guard assets.indices.contains(orderedIndex) else {
            return nil
        }

        switch sortOrder {
        case .oldestFirst:
            return assets[orderedIndex]
        case .newestFirst:
            return assets[assets.count - orderedIndex - 1]
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PhotoDetailPager
        var isInteractiveTransition = false
        private var controllers: [String: WeakPhotoDetailPageController] = [:]

        init(parent: PhotoDetailPager) {
            self.parent = parent
        }

        func controller(at index: Int) -> UIHostingController<PhotoDetailPage>? {
            guard let asset = parent.asset(at: index) else {
                return nil
            }
            if let controller = controllers[asset.id]?.value {
                return controller
            }

            let controller = UIHostingController(
                rootView: PhotoDetailPage(
                    asset: asset,
                    model: parent.modelStore.model(for: asset.id),
                    showsChineseKeys: parent.$showsChineseKeys
                )
            )
            controller.view.backgroundColor = .clear
            controllers[asset.id] = WeakPhotoDetailPageController(controller)
            controllers = controllers.filter { $0.value.value != nil }
            return controller
        }

        func assetID(for viewController: UIViewController) -> String? {
            (viewController as? UIHostingController<PhotoDetailPage>)?.rootView.asset.id
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let assetID = assetID(for: viewController),
                  let index = parent.orderedIndex(of: assetID),
                  index > 0 else {
                return nil
            }
            return controller(at: index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let assetID = assetID(for: viewController),
                  let index = parent.orderedIndex(of: assetID),
                  index < parent.assets.count - 1 else {
                return nil
            }
            return controller(at: index + 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            isInteractiveTransition = true
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            isInteractiveTransition = false
            guard completed,
                  let visibleController = pageViewController.viewControllers?.first,
                  let assetID = assetID(for: visibleController) else {
                return
            }
            parent.currentAssetID = assetID
        }
    }
}

private final class PhotoDetailPageViewController: UIPageViewController {
    private weak var configuredNavigationController: UINavigationController?
    private var previousStandardAppearance: UINavigationBarAppearance?
    private var previousScrollEdgeAppearance: UINavigationBarAppearance?
    private var previousCompactAppearance: UINavigationBarAppearance?
    private var previousCompactScrollEdgeAppearance: UINavigationBarAppearance?
    private var previousIsTranslucent = false
    private var isShowingTransparentNavigationBar = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isShowingTransparentNavigationBar = true
        applyTransparentNavigationBarAppearance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyTransparentNavigationBarAppearance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        isShowingTransparentNavigationBar = false
        restoreNavigationBarAppearance()
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if isShowingTransparentNavigationBar {
            applyTransparentNavigationBarAppearance()
        }
    }

    func updateNavigationBarAppearanceIfVisible() {
        guard isShowingTransparentNavigationBar else {
            return
        }
        applyTransparentNavigationBarAppearance()
    }

    private func applyTransparentNavigationBarAppearance() {
        guard let navigationController else {
            return
        }

        let navigationBar = navigationController.navigationBar
        if configuredNavigationController !== navigationController {
            restoreNavigationBarAppearance()
            configuredNavigationController = navigationController
            previousStandardAppearance = navigationBar.standardAppearance
            previousScrollEdgeAppearance = navigationBar.scrollEdgeAppearance
            previousCompactAppearance = navigationBar.compactAppearance
            previousCompactScrollEdgeAppearance = navigationBar.compactScrollEdgeAppearance
            previousIsTranslucent = navigationBar.isTranslucent
        }

        let transparentAppearance = UINavigationBarAppearance()
        transparentAppearance.configureWithTransparentBackground()
        transparentAppearance.backgroundColor = .clear
        transparentAppearance.backgroundEffect = nil
        transparentAppearance.shadowColor = .clear

        navigationBar.standardAppearance = transparentAppearance
        navigationBar.scrollEdgeAppearance = transparentAppearance
        navigationBar.compactAppearance = transparentAppearance
        navigationBar.compactScrollEdgeAppearance = transparentAppearance
        navigationBar.isTranslucent = true

        if let navigationItem = navigationController.topViewController?.navigationItem {
            navigationItem.standardAppearance = transparentAppearance
            navigationItem.scrollEdgeAppearance = transparentAppearance
            navigationItem.compactAppearance = transparentAppearance
            navigationItem.compactScrollEdgeAppearance = transparentAppearance
        }
    }

    private func restoreNavigationBarAppearance() {
        guard let navigationController = configuredNavigationController else {
            return
        }

        let navigationBar = navigationController.navigationBar
        if let previousStandardAppearance {
            navigationBar.standardAppearance = previousStandardAppearance
        }
        navigationBar.scrollEdgeAppearance = previousScrollEdgeAppearance
        navigationBar.compactAppearance = previousCompactAppearance
        navigationBar.compactScrollEdgeAppearance = previousCompactScrollEdgeAppearance
        navigationBar.isTranslucent = previousIsTranslucent

        configuredNavigationController = nil
        previousStandardAppearance = nil
        previousScrollEdgeAppearance = nil
        previousCompactAppearance = nil
        previousCompactScrollEdgeAppearance = nil
    }
}

private final class WeakPhotoDetailPageController {
    weak var value: UIHostingController<PhotoDetailPage>?

    init(_ value: UIHostingController<PhotoDetailPage>) {
        self.value = value
    }
}

enum MetadataLanguagePreference {
    static var defaultShowsChineseKeys: Bool {
        guard let preferredLanguage = Locale.preferredLanguages.first else {
            return false
        }

        return Locale(identifier: preferredLanguage).language.languageCode?.identifier == "zh"
    }
}

#endif
