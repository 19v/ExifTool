#if os(macOS)

import AppKit
import SwiftUI

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ExifToolApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @FocusedValue(\.macPhotoWorkspace) private var workspace
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Group {
            WindowGroup {
                MacRootView()
            }

            WindowGroup("照片查看", id: macPhotoViewerWindowID, for: String.self) { filePath in
                MacRootView(
                    initialFileURLs: filePath.wrappedValue.map {
                        [URL(fileURLWithPath: $0)]
                    } ?? []
                )
            }

            Settings {
                MacSettingsTabView()
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("打开…") {
                    workspace?.pickFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(workspace == nil)

                Button("在新窗口中打开当前照片") {
                    guard let filePath = workspace?.currentFilePath else {
                        return
                    }

                    openWindow(id: macPhotoViewerWindowID, value: filePath)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(workspace?.currentFilePath == nil)
            }

            CommandMenu("照片") {
                Button("上一张") {
                    workspace?.selectPreviousAsset()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(workspace?.canSelectPreviousAsset ?? false))

                Button("下一张") {
                    workspace?.selectNextAsset()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(workspace?.canSelectNextAsset ?? false))

                Divider()

                Button("在 Finder 中显示") {
                    workspace?.revealCurrentFileInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!(workspace?.hasCurrentFile ?? false))

                Button("复制路径") {
                    workspace?.copyCurrentFilePath()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!(workspace?.hasCurrentFile ?? false))

                Button("默认应用打开") {
                    workspace?.openCurrentFileInDefaultApp()
                }
                .disabled(!(workspace?.hasCurrentFile ?? false))

                Divider()

                if (workspace?.recentFiles ?? []).isEmpty {
                    Button("没有最近文件") { }
                        .disabled(true)
                } else {
                    ForEach(workspace?.recentFiles ?? [], id: \.self) { url in
                        Button(url.lastPathComponent) {
                            Task {
                                _ = await workspace?.openRecentFile(url)
                            }
                        }
                    }

                    Divider()

                    Button("清除最近记录") {
                        workspace?.clearRecentFiles()
                    }
                }
            }
        }
    }
}

#endif
