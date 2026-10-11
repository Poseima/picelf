import XCTest
import AppKit
import ImageIO
@testable import Picelf

@MainActor
final class WorkbenchTransferTests: XCTestCase {
    private var root: URL!
    private var downloads: URL!
    private var prefs: AppPreferences!
    private var store: WorkbenchStore!
    private var pasteboard: NSPasteboard!
    private var suite: String!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("picelf-transfer-\(UUID())")
        downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        suite = "com.picelf.tests.transfer.\(UUID())"
        prefs = AppPreferences(defaults: UserDefaults(suiteName: suite)!)
        prefs.watermarkConfig.isEnabled = false
        prefs.defaultFormat = .png
        pasteboard = .withUniqueName()
        store = WorkbenchStore(outputDirectory: root.appendingPathComponent("Results"),
                               jobsFileURL: root.appendingPathComponent("jobs.json"), preferences: prefs,
                               now: { Date(timeIntervalSince1970: 1_800_000_000) },
                               downloadsDirectory: downloads, clipboard: pasteboard)
    }
    override func tearDown() async throws {
        store.shutdownForTesting()
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func image(width: Int = 73, height: Int = 2001) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        for y in 0..<height { for x in 0..<width {
            let i = y * rep.bytesPerRow + x * 4
            rep.bitmapData![i] = UInt8((x * 13 + y) % 256)
            rep.bitmapData![i + 1] = UInt8((y * 7) % 256)
            rep.bitmapData![i + 2] = 99
            rep.bitmapData![i + 3] = x < 10 ? 0 : 255
        } }
        return NSImage(cgImage: rep.cgImage!, size: NSSize(width: width, height: height))
    }
    private func bitmap(_ data: Data) throws -> NSBitmapImageRep { try XCTUnwrap(NSBitmapImageRep(data: data)) }
    private func assertContent(_ data: Data, matches source: NSImage, file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try bitmap(data)
        let expected = NSBitmapImageRep(cgImage: source.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        XCTAssertEqual(actual.pixelsWide, expected.pixelsWide, file: file, line: line)
        XCTAssertEqual(actual.pixelsHigh, expected.pixelsHigh, file: file, line: line)
        XCTAssertEqual(actual.colorAt(x: 2, y: 20)?.alphaComponent, 0, file: file, line: line)
        for point in [(20, 20), (30, 1000), (70, 1999)] {
            let a = try XCTUnwrap(actual.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
            let e = try XCTUnwrap(expected.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
            XCTAssertEqual(a.redComponent, e.redComponent, accuracy: 0.01, file: file, line: line)
            XCTAssertEqual(a.greenComponent, e.greenComponent, accuracy: 0.01, file: file, line: line)
        }
    }

    func testCopyPastePreservesFullPixelsAndTransparency() async throws {
        let source = image()
        let idResult = await store.importImage(source, sourceName: "original")
        let id = try XCTUnwrap(idResult)
        XCTAssertTrue(store.copyResultToClipboard(jobID: id))
        try assertContent(XCTUnwrap(pasteboard.data(forType: .png)), matches: source)
        let copies = await store.importFromPasteboard()
        XCTAssertEqual(copies.count, 1)
        XCTAssertNotEqual(copies.first, id)
        let url = try XCTUnwrap(store.jobs.first?.outputURL)
        try assertContent(Data(contentsOf: url), matches: source)
    }

    func testQueuedPastesUseTheirOwnSnapshotsInTriggerOrderAndProtectUpdates() async throws {
        let controller = WorkbenchClipboardController(store: store)
        let first = image()
        pasteboard.setData(NSBitmapImageRep(cgImage: first.cgImage(forProposedRect: nil, context: nil, hints: nil)!).representation(using: .png, properties: [:])!, forType: .png)
        let a = try XCTUnwrap(controller.paste(from: pasteboard))
        pasteboard.clearContents()
        let second = image(width: 99, height: 100)
        pasteboard.setData(second.tiffRepresentation!, forType: .tiff)
        let b = try XCTUnwrap(controller.paste(from: pasteboard))
        pasteboard.clearContents()
        pasteboard.setString("ordinary text", forType: .string)
        XCTAssertNil(controller.paste(from: pasteboard))
        XCTAssertEqual(store.transferCount, 2)
        XCTAssertNotNil(UpdateActivity(jobs: store.hasActiveWork).blockingReason)
        await a.value
        await b.value
        XCTAssertEqual(store.transferCount, 0)
        XCTAssertFalse(store.hasActiveWork)
        XCTAssertEqual(store.jobs.count, 2)
        XCTAssertEqual(try bitmap(Data(contentsOf: XCTUnwrap(store.jobs[0].outputURL))).pixelsWide, 99)
        try assertContent(Data(contentsOf: XCTUnwrap(store.jobs[1].outputURL)), matches: first)
        XCTAssertEqual(controller.importedJobID, store.jobs[0].id)
    }

    func testInvalidClipboardAndFileImports() async throws {
        pasteboard.setData(Data([1, 2, 3]), forType: .png)
        let invalid = await store.importFromPasteboard()
        XCTAssertTrue(invalid.isEmpty)
        let source = image()
        let file = root.appendingPathComponent("external.png")
        try ImageExporter.export(source, to: file, format: .png)
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        let ids = await store.importFromPasteboard()
        XCTAssertEqual(ids.count, 1)
        try assertContent(Data(contentsOf: XCTUnwrap(store.jobs.first?.outputURL)), matches: source)
        XCTAssertEqual(store.transferCount, 0)
    }

    func testSelectionCannotCopyHiddenDeletedOrVideoJobs() async throws {
        let idResult = await store.importImage(image(), sourceName: "selected")
        let id = try XCTUnwrap(idResult)
        let controller = WorkbenchClipboardController(store: store)
        controller.reconcileSelection(displayedIDs: [id])
        XCTAssertTrue(controller.canCopy)
        controller.reconcileSelection(displayedIDs: [])
        controller.selectedJobID = id // Stale UI state cannot bypass visibility validation.
        XCTAssertFalse(controller.canCopy)
        controller.reconcileSelection(displayedIDs: [id])
        store.remove(jobID: id)
        XCTAssertFalse(controller.canCopy)
        let pending = store.addCompletedSnap(image: image(), windowInfo: nil,
                                             captureRect: CGRect(x: 0, y: 0, width: 73, height: 2001))
        controller.reconcileSelection(displayedIDs: [pending])
        XCTAssertFalse(controller.canCopy)
        XCTAssertTrue(store.hasActiveWork, "Saving a captured image must also block an update restart")
        let file = root.appendingPathComponent("video.mov")
        try Data([0]).write(to: file)
        let videoResult = await store.importVideo(from: file, sourceName: "video")
        let video = try XCTUnwrap(videoResult)
        controller.reconcileSelection(displayedIDs: [video])
        XCTAssertFalse(controller.canCopy)
    }

    func testConcurrentDownloadsNeverOverwriteAndSurviveHistoryDeletion() async throws {
        let source = image()
        let idResult = await store.importImage(source, sourceName: "export")
        let id = try XCTUnwrap(idResult)
        let previousSavePath = prefs.savePath
        async let a = store.saveResultToDownloads(jobID: id)
        async let b = store.saveResultToDownloads(jobID: id)
        async let c = store.saveResultToDownloads(jobID: id)
        let urls = try await [a, b, c]
        XCTAssertEqual(Set(urls).count, 3)
        XCTAssertTrue(urls.contains { $0.lastPathComponent.contains(" (2)") })
        XCTAssertTrue(urls.contains { $0.lastPathComponent.contains(" (3)") })
        for url in urls { try assertContent(Data(contentsOf: url), matches: source) }
        store.remove(jobID: id)
        for url in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertEqual(prefs.savePath, previousSavePath)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: downloads.path).contains { $0.hasSuffix(".tmp") })
        XCTAssertEqual(store.transferCount, 0)
    }

    func testExistingFilenameAndDifferentImageArePreserved() async throws {
        let firstResult = await store.importImage(image(), sourceName: "first")
        let first = try XCTUnwrap(firstResult)
        let firstURL = try await store.saveResultToDownloads(jobID: first)
        let original = try Data(contentsOf: firstURL)
        let otherResult = await store.importImage(image(width: 99, height: 111), sourceName: "other")
        let other = try XCTUnwrap(otherResult)
        let otherURL = try await store.saveResultToDownloads(jobID: other)
        XCTAssertTrue(otherURL.lastPathComponent.hasSuffix(" (2).png"))
        XCTAssertEqual(try Data(contentsOf: firstURL), original)
        XCTAssertEqual(try bitmap(Data(contentsOf: otherURL)).pixelsWide, 99)
        XCTAssertEqual(store.jobs.count, 2)
    }

    func testPublicationFailureRemovesCompletedTemporaryFile() async throws {
        store.shutdownForTesting()
        store = WorkbenchStore(outputDirectory: root.appendingPathComponent("Results"),
            jobsFileURL: root.appendingPathComponent("jobs.json"), preferences: prefs,
            downloadsDirectory: downloads, clipboard: pasteboard,
            downloadPublisher: { temporary, _ in
                XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path))
                XCTAssertNotNil(NSBitmapImageRep(data: try Data(contentsOf: temporary)))
                throw CocoaError(.fileWriteNoPermission)
            })
        let result = await store.importImage(image(), sourceName: "failure")
        let id = try XCTUnwrap(result)
        do { _ = try await store.saveResultToDownloads(jobID: id); XCTFail("Must fail") }
        catch { XCTAssertEqual((error as NSError).code, CocoaError.fileWriteNoPermission.rawValue) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: downloads.path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.jobs.first?.outputURL).path))
        XCTAssertEqual(store.transferCount, 0)
    }

    func testJPEGQualityAndWatermarkUseExportPreferences() async throws {
        let source = makeStripedImage(width: 512, height: 512)
        let idResult = await store.importImage(source, sourceName: "jpeg")
        let id = try XCTUnwrap(idResult)
        prefs.defaultFormat = .jpeg
        prefs.jpegQuality = 0.15
        let low = try await store.saveResultToDownloads(jobID: id)
        prefs.jpegQuality = 0.95
        let high = try await store.saveResultToDownloads(jobID: id)
        XCTAssertEqual(high.pathExtension, "jpg")
        let lowData = try Data(contentsOf: low), highData = try Data(contentsOf: high)
        XCTAssertGreaterThan(highData.count, lowData.count)
        XCTAssertEqual(lowData.prefix(2), Data([0xff, 0xd8]))
        XCTAssertEqual(try bitmap(highData).pixelsWide, 512)
        prefs.defaultFormat = .png
        prefs.watermarkConfig.isEnabled = true
        prefs.watermarkConfig.text = "Test watermark"
        let watermarked = try await store.saveResultToDownloads(jobID: id)
        let expected = WatermarkRenderer.apply(to: source, config: prefs.watermarkConfig)
        let expectedURL = root.appendingPathComponent("expected.png")
        try ImageExporter.export(expected, to: expectedURL, format: .png)
        XCTAssertEqual(try Data(contentsOf: watermarked), try Data(contentsOf: expectedURL))
    }

    func testMissingFileAndWriteFailureCleanUpAndReleaseBusyState() async throws {
        let idResult = await store.importImage(image(), sourceName: "missing")
        let id = try XCTUnwrap(idResult)
        let managed = try XCTUnwrap(store.jobs.first?.outputURL)
        try FileManager.default.removeItem(at: managed)
        do { _ = try await store.saveResultToDownloads(jobID: id); XCTFail("Must fail") } catch {}
        XCTAssertEqual(store.transferCount, 0)
        let otherResult = await store.importImage(image(), sourceName: "write failure")
        let other = try XCTUnwrap(otherResult)
        try FileManager.default.removeItem(at: downloads)
        try Data([1]).write(to: downloads) // File in place of the directory, deterministic write failure.
        do { _ = try await store.saveResultToDownloads(jobID: other); XCTFail("Must fail") } catch {}
        XCTAssertEqual(store.transferCount, 0)
        XCTAssertEqual(try Data(contentsOf: downloads), Data([1]))
    }
}
