# ExifTool

ExifTool 是一款使用 SwiftUI 编写的 iOS 与 macOS 照片元数据查看器。它以只读方式解析照片，通过 ImageIO 获取标准图像属性，并补充 Fujifilm、Nikon 和 Sony MakerNote 的专用解析。

> 本项目虽然名为 ExifTool，但没有集成 Phil Harvey 的 `exiftool` 可执行文件或命令行工具。当前版本不会修改或写回照片元数据。

## 功能

### iOS

- 浏览系统照片图库和相册，兼容完整、受限及拒绝图库权限的场景
- 无需完整图库权限即可通过系统照片选择器打开照片
- 按文件名、日期、尺寸或照片标识符搜索照片
- 可选择仅显示已经下载到本机的照片
- 默认不联网读取 iCloud 原图，需要时可由用户明确允许下载
- 通过 Share Extension 从其他应用将单张图片发送到 ExifTool
- 分享原始照片或元数据文本

### macOS

- 通过拖放、文件选择器、菜单或“打开方式”导入图片
- 支持多文件工作区、排序、最近打开记录和多窗口查看
- 并排比较两张照片的元数据并突出显示差异
- 复制或导出 Markdown 格式的对比报告
- 在 Finder 中定位文件、复制路径或使用默认应用打开原文件

### 元数据

- 读取 ImageIO 支持的图片格式，包括其能够识别的常见图片和 RAW 文件
- 展示 TIFF、Exif、GPS 等标准属性
- 自研 Fujifilm、Nikon 和 Sony MakerNote 解析器
- 元数据显示支持分区、筛选、中文键名和值转换
- 大文件优先使用临时文件和流式读取，临时资源会按策略清理

## 系统与开发环境

| 项目 | 要求 |
| --- | --- |
| iPhone / iPad | iOS 18.0 或更高版本 |
| Mac | macOS 15.0 或更高版本 |
| Xcode | Xcode 26 或更高版本 |
| Swift | Swift 6，启用完整严格并发检查 |

项目不依赖第三方包，使用的框架均来自 Apple SDK。

## 构建

1. 使用 Xcode 打开 `ExifTool.xcodeproj`。
2. 选择共享 scheme `ExifTool`。
3. 选择 iOS 模拟器、iOS 设备或 My Mac 后运行。

使用命令行构建 iOS 主应用及其 Share Extension：

```sh
xcodebuild \
  -project ExifTool.xcodeproj \
  -scheme ExifTool \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

真机运行需要在 Xcode 中配置自己的开发团队，并确保主应用与 Share Extension 使用同一个 App Group。

## 测试

测试覆盖厂商 MakerNote 解析、照片搜索、增量图库更新、异步取消与缓存、元数据显示投影和 macOS 元数据对比，并记录大型搜索与增量集合更新的耗时和内存指标。运行 macOS 测试：

```sh
xcodebuild \
  -project ExifTool.xcodeproj \
  -scheme ExifTool \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

GitHub Actions 会验证中英文字符串目录、隐私清单与 RAW 测试样本校验和，运行 macOS/iOS 测试，并构建和归档包含 Share Extension 的应用。

## 项目结构

```text
ExifTool/
├── Metadata/          标准元数据与厂商 MakerNote 解析
├── Models/            照片、搜索和元数据显示模型
└── Views/
    ├── Common/        跨平台复用视图
    ├── iOS/           iOS 图库、搜索、详情和服务
    └── macOS/         macOS 文件工作区、详情和对比
ExifToolTests/         解析器和业务模型测试
ShareExtension/        iOS 分享扩展
```

## 隐私与数据处理

- 照片和元数据解析均在设备本地完成。
- 应用不会写入或修改原始照片。
- iCloud 原图下载由用户设置控制。
- 分享扩展通过 App Group 传递临时文件；过期文件及应用创建的其他临时资源会自动清理。

## 本地化

界面目前提供简体中文和英文。主应用与 Share Extension 分别维护自己的 String Catalog。

## 许可证

本项目使用 [GNU General Public License v3.0](LICENSE)。
