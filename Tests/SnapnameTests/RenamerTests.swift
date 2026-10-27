import XCTest
@testable import Snapname

final class RenamerTests: XCTestCase {
    func testSanitizeMakesSafeHyphenatedNames() {
        XCTAssertEqual(Renamer.sanitize("GitHub Log-in: Acme Corp!"), "github-log-in-acme-corp")
        XCTAssertEqual(Renamer.sanitize("debt-tracking-report-overview"), "debt-tracking-report-overview")
        XCTAssertEqual(Renamer.sanitize("../../etc/passwd"), "etc-passwd")
        XCTAssertEqual(Renamer.sanitize("café menü"), "cafe-menu")
        XCTAssertNil(Renamer.sanitize("  —!? "))
    }

    func testSanitizeStopsAtWholeWords() {
        let name = Renamer.sanitize(String(repeating: "word ", count: 30), maxLength: 12)
        XCTAssertEqual(name, "word-word")
    }

    func testUniqueURLAddsCounter() {
        let folder = URL(fileURLWithPath: "/tmp/shots")
        let taken: Set<String> = ["/tmp/shots/chart.png", "/tmp/shots/chart-2.png"]
        let url = Renamer.uniqueURL(in: folder, name: "chart", ext: "png") { taken.contains($0.path) }
        XCTAssertEqual(url.path, "/tmp/shots/chart-3.png")
    }

    func testRecognizesScreenshotNames() {
        XCTAssertTrue(Renamer.isScreenshot(URL(fileURLWithPath: "/x/Screenshot 2026-10-27 at 4.53.36 PM.png")))
        XCTAssertTrue(Renamer.isScreenshot(URL(fileURLWithPath: "/x/Screenshot iPhone 17 Pro 24-10-2026 at 12.44.26 PM.PNG")))
        XCTAssertTrue(Renamer.isScreenshot(URL(fileURLWithPath: "/x/Screen Shot 2020-01-01 at 9.00.00 AM.jpg")))
        XCTAssertFalse(Renamer.isScreenshot(URL(fileURLWithPath: "/x/.Screenshot 2026-10-27 at 4.53.36 PM.png")))
        XCTAssertFalse(Renamer.isScreenshot(URL(fileURLWithPath: "/x/Screenshot 2026-10-27 at 4.53.36 PM.mov")))
        XCTAssertFalse(Renamer.isScreenshot(URL(fileURLWithPath: "/x/holiday.png")))
    }

    func testRenameKeepsOriginalNameAndSkipsDoneFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("Screenshot 2026-10-27 at 4.53.36 PM.png")
        try Data([1, 2, 3]).write(to: original)
        XCTAssertEqual(Renamer.pending(in: folder).map(\.lastPathComponent), [original.lastPathComponent])

        let renamed = try Renamer.rename(original, to: "loan-report", description: "A loan report.")

        XCTAssertEqual(renamed.lastPathComponent, "loan-report.png")
        XCTAssertEqual(try Data(contentsOf: renamed), Data([1, 2, 3]))
        XCTAssertTrue(Renamer.isRenamed(renamed))
        XCTAssertEqual(Renamer.pending(in: folder), [])
    }

    func testParsesModelReply() throws {
        let body = #"{"message":{"role":"assistant","content":"{\"name\": \"chart\", \"description\": \"A chart.\"}"}}"#
        XCTAssertEqual(try Namer.parse(Data(body.utf8)), Namer.Result(name: "chart", description: "A chart."))
        XCTAssertThrowsError(try Namer.parse(Data("nope".utf8)))
    }
}
