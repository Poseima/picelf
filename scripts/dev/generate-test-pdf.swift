import AppKit
import PDFKit

let output = CommandLine.arguments.dropFirst().first ?? "Tests/PicelfCoreTests/Fixtures/scroll-test.pdf"
let url = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
let document = PDFDocument()
for page in 0..<20 {
    let image = NSImage(size: NSSize(width: 800, height: 1100))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 800, height: 1100).fill()
    for row in 0..<24 {
        let number = page * 24 + row
        let text = "Section \(number) — Synthetic capture fixture — \(number * 7919)"
        text.draw(at: NSPoint(x: 42, y: 1040 - row * 42), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular),
            .foregroundColor: NSColor.black
        ])
        NSColor(calibratedHue: CGFloat(number % 97) / 97, saturation: 0.5, brightness: 0.8, alpha: 1).setFill()
        NSRect(x: 620, y: CGFloat(1030 - row * 42), width: CGFloat(40 + number % 120), height: 20).fill()
    }
    image.unlockFocus()
    guard let pdfPage = PDFPage(image: image) else { fatalError("Unable to create test page") }
    document.insert(pdfPage, at: page)
}
guard document.write(to: url) else { fatalError("Unable to write PDF") }
print("Wrote anonymous 20-page PDF: \(url.path)")
