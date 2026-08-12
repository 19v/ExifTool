import Foundation
import os

nonisolated enum PerformanceInstrumentation {
    static let signposter = OSSignposter(
        subsystem: "com.echopie.ExifTool",
        category: "Performance"
    )
}
