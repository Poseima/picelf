import XCTest
import AppKit
@testable import Picelf

@MainActor
final class RelayClipboardTests: XCTestCase {
    func testImagePasteboardContainsActualPNGAndInvalidInputPreservesClipboard() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Keep this if export fails", forType: .string)
        XCTAssertThrowsError(try RelayMacController.writePNG(Data([0, 1, 2]), to: board))
        XCTAssertEqual(board.string(forType: .string), "Keep this if export fails")
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let png = try RelayImage.png(XCTUnwrap(ctx.makeImage()))
        try RelayMacController.writePNG(png, to: board)
        XCTAssertEqual(board.data(forType: .png), png)
        XCTAssertNotNil(NSImage(pasteboard: board))
        XCTAssertNil(board.string(forType: .fileURL))
    }
}
