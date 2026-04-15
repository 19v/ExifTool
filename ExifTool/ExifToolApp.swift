//
//  ExifToolApp.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

import SwiftUI

@main
struct ExifToolApp: App {
    #if os(macOS)
    @FocusedValue(\.macPhotoWorkspace) private var macWorkspace
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Scene {
        Group {
            WindowGroup {
                ContentView()
            }
            #if os(macOS)
            WindowGroup("照片查看", id: macPhotoViewerWindowID, for: String.self) { filePath in
                ContentView(
                    initialFileURLs: {
                        if let path = filePath.wrappedValue {
                            return [URL(fileURLWithPath: path)]
                        }

                        return []
                    }()
                )
            }
            #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("打开…") {
                    macWorkspace?.pickFiles()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(macWorkspace == nil)

                Button("在新窗口中打开当前照片") {
                    guard let filePath = macWorkspace?.currentFilePath else {
                        return
                    }

                    openWindow(id: macPhotoViewerWindowID, value: filePath)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(macWorkspace?.currentFilePath == nil)
            }

            CommandMenu("照片") {
                Button("上一张") {
                    macWorkspace?.selectPreviousAsset()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(macWorkspace?.canSelectPreviousAsset ?? false))

                Button("下一张") {
                    macWorkspace?.selectNextAsset()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(macWorkspace?.canSelectNextAsset ?? false))

                Divider()

                Button("在 Finder 中显示") {
                    macWorkspace?.revealCurrentFileInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!(macWorkspace?.hasCurrentFile ?? false))

                Button("复制路径") {
                    macWorkspace?.copyCurrentFilePath()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!(macWorkspace?.hasCurrentFile ?? false))

                Button("默认应用打开") {
                    macWorkspace?.openCurrentFileInDefaultApp()
                }
                .disabled(!(macWorkspace?.hasCurrentFile ?? false))

                Divider()

                if (macWorkspace?.recentFiles ?? []).isEmpty {
                    Button("没有最近文件") { }
                        .disabled(true)
                } else {
                    ForEach(macWorkspace?.recentFiles ?? [], id: \.self) { url in
                        Button(url.lastPathComponent) {
                            _ = macWorkspace?.openRecentFile(url)
                        }
                    }

                    Divider()

                    Button("清除最近记录") {
                        macWorkspace?.clearRecentFiles()
                    }
                }
            }
        }
        #endif
    }
}
