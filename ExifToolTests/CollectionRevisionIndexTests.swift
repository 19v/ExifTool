import Testing
@testable import ExifTool

struct CollectionRevisionIndexTests {
    @Test func onlyMarkedCollectionsAdvance() {
        var index = CollectionRevisionIndex()

        index.markChanged(["first", "first", "second"])
        index.markChanged(["second"])

        #expect(index["first"] == 1)
        #expect(index["second"] == 2)
        #expect(index["untouched"] == 0)
    }

    @Test func removedCollectionsArePrunedWithoutChangingRetainedRevisions() {
        var index = CollectionRevisionIndex()
        index.markChanged(["retained", "removed"])

        index.retainOnly(["retained", "new"])

        #expect(index["retained"] == 1)
        #expect(index["removed"] == 0)
        #expect(index["new"] == 0)
    }
}
