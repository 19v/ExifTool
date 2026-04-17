//
//  MacPhotoDropPlaceholder.swift
//  ExifTool
//
//  Created by Haochen on 2026/4/12.
//

#if os(macOS)

import SwiftUI

struct MacPhotoDropPlaceholder: View {
    let isDropTargeted: Bool
    let recentFiles: [URL]
    let onPickFiles: () -> Void
    let onOpenRecentFile: (URL) -> Void
    let onClearRecentFiles: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)

            Text("拖入照片开始查看 Exif")
                .font(.title3.weight(.semibold))

            Text("把 JPEG、HEIC、PNG、TIFF 等图片文件直接拖到窗口里，应用会立即显示预览和元数据。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("选择文件") {
                onPickFiles()
            }
            .buttonStyle(.borderedProminent)

            Text("也可以直接按 Cmd+O 选择文件。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("最近打开")
                            .font(.headline)

                        Spacer()

                        Button("清除") {
                            onClearRecentFiles()
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(recentFiles, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            onOpenRecentFile(url)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.platformSecondaryBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [8, 8]))
                }
                .padding(24)
        )
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
    }
}

#endif
