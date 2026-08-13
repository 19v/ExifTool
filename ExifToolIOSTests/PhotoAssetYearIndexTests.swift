#if os(iOS)

import XCTest
@testable import ExifTool

final class PhotoAssetYearIndexTests: XCTestCase {
    @MainActor
    func testYearsAreUniqueSortedDescendingAndIgnoreMissingDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let assets = [
            makeAsset(id: "newest", year: 2026, calendar: calendar),
            makeAsset(id: "duplicate", year: 2026, calendar: calendar),
            makeAsset(id: "older", year: 2024, calendar: calendar),
            makeAsset(id: "undated", year: nil, calendar: calendar)
        ]

        XCTAssertEqual(PhotoAssetYearIndex.years(in: assets, calendar: calendar), [2026, 2024])
    }

    @MainActor
    private func makeAsset(id: String, year: Int?, calendar: Calendar) -> PhotoAsset {
        let creationDate = year.flatMap {
            calendar.date(from: DateComponents(year: $0, month: 6, day: 15))
        }
        return PhotoAsset(file: LocalPhotoFile(
            id: id,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            fileName: "\(id).jpg",
            data: nil,
            creationDate: creationDate,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1
        ))
    }
}

#endif
