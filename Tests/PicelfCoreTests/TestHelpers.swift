import CoreGraphics
import AppKit

/// Generate a test image with colored horizontal stripes.
func makeStripedImage(
    width: Int,
    height: Int,
    stripeHeight: Int = 20,
    colors: [NSColor] = [.red, .blue, .green, .yellow, .cyan, .magenta]
) -> NSImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    for y in stride(from: 0, to: height, by: stripeHeight) {
        let colorIdx = (y / stripeHeight) % colors.count
        context.setFillColor(colors[colorIdx].cgColor)
        context.fill(CGRect(x: 0, y: y, width: width, height: min(stripeHeight, height - y)))
    }
    let cgImage = context.makeImage()!
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
}

/// Generate a test image where each row has a unique pseudo-random color.
/// Unlike striped images, this has NO repeating patterns, so the overlap
/// detector can only find the one true overlap — no ambiguity.
///
/// Uses different prime moduli per channel so the combined (R,G,B) tuple
/// doesn't repeat until row ~14.4M (lcm(251, 241, 239)).
func makeUniqueRowImage(width: Int, height: Int) -> NSImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    for y in 0..<height {
        let r = CGFloat((y * 73 + 29) % 251) / 250.0
        let g = CGFloat((y * 151 + 97) % 241) / 240.0
        let b = CGFloat((y * 37 + 173) % 239) / 238.0
        context.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
        context.fill(CGRect(x: 0, y: y, width: width, height: 1))
    }
    let cgImage = context.makeImage()!
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
}

/// Create two overlapping test frames from a single tall image.
func makeOverlappingFrames(
    width: Int = 200, frameHeight: Int = 100, overlapRows: Int = 30, stripeHeight: Int = 10
) -> (frameA: NSImage, frameB: NSImage) {
    let totalHeight = 2 * frameHeight - overlapRows
    let fullImage = makeUniqueRowImage(width: width, height: totalHeight)
    // For NSImage, we'll crop by drawing portions
    let frameA = cropNSImage(fullImage, to: CGRect(x: 0, y: 0, width: width, height: frameHeight))
    let frameB = cropNSImage(fullImage, to: CGRect(x: 0, y: frameHeight - overlapRows, width: width, height: frameHeight))
    return (frameA, frameB)
}

/// Crop an NSImage to a rect (in CG coordinates, y=0 at bottom)
private func cropNSImage(_ image: NSImage, to rect: CGRect) -> NSImage {
    let cropped = NSImage(size: rect.size)
    cropped.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
               from: NSRect(x: rect.origin.x, y: image.size.height - rect.origin.y - rect.height,
                            width: rect.width, height: rect.height),
               operation: .copy, fraction: 1.0)
    cropped.unlockFocus()
    return cropped
}

extension NSImage {
    var width: Int {
        cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? Int(size.width)
    }
    var height: Int {
        cgImage(forProposedRect: nil, context: nil, hints: nil)?.height ?? Int(size.height)
    }

    func toNSImage() -> NSImage { self }
}

func makeScrollingFrames(
    width: Int,
    frameHeight: Int,
    overlapRows: Int,
    frameCount: Int
) -> (frames: [NSImage], expectedHeight: Int) {
    let expectedHeight = frameHeight + max(0, frameCount - 1) * (frameHeight - overlapRows)
    let fullHeight = expectedHeight
    let full = makeUniqueRowImage(width: width, height: fullHeight)
    var frames: [NSImage] = []
    for idx in 0..<frameCount {
        let y = idx * (frameHeight - overlapRows)
        let frame = cropNSImage(full, to: CGRect(x: 0, y: y, width: width, height: frameHeight))
        frames.append(frame)
    }
    return (frames, expectedHeight)
}

func makeNoisyImage(_ image: NSImage, amplitude: Int, seed: UInt64) -> NSImage {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return image
    }
    let width = cg.width
    let height = cg.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return image
    }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

    var state = seed == 0 ? 1 : seed
    func nextRandom() -> Int {
        state = state &* 2862933555777941757 &+ 3037000493
        return Int((state >> 33) & 0x7fff_ffff)
    }

    if amplitude > 0 {
        for i in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 {
                let delta = (nextRandom() % (2 * amplitude + 1)) - amplitude
                let value = Int(pixels[i + channel]) + delta
                pixels[i + channel] = UInt8(max(0, min(255, value)))
            }
        }
    }

    guard let outCtx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let outCG = outCtx.makeImage() else {
        return image
    }
    return NSImage(cgImage: outCG, size: NSSize(width: width, height: height))
}

func makeFramesWithToolbar(
    width: Int,
    frameHeight: Int,
    toolbarHeight: Int,
    overlapRows: Int,
    frameCount: Int
) -> (frames: [NSImage], expectedContentHeight: Int, toolbarHeight: Int) {
    let contentHeight = frameHeight - toolbarHeight
    let expectedContentHeight = contentHeight + max(0, frameCount - 1) * (contentHeight - overlapRows)
    let fullContent = makeUniqueRowImage(width: width, height: expectedContentHeight)
    var frames: [NSImage] = []
    for idx in 0..<frameCount {
        let y = idx * (contentHeight - overlapRows)
        let contentSlice = cropNSImage(
            fullContent,
            to: CGRect(x: 0, y: y, width: width, height: contentHeight)
        )
        let composed = NSImage(size: NSSize(width: width, height: frameHeight))
        composed.lockFocus()
        NSColor(white: 0.92, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: frameHeight - toolbarHeight, width: width, height: toolbarHeight)).fill()
        contentSlice.draw(in: NSRect(x: 0, y: 0, width: width, height: contentHeight))
        composed.unlockFocus()
        frames.append(composed)
    }
    return (frames, expectedContentHeight, toolbarHeight)
}

func makeFramesWithStaticRegions(
    width: Int,
    frameHeight: Int,
    topStaticHeight: Int,
    bottomStaticHeight: Int,
    overlapRows: Int,
    frameCount: Int
) -> (frames: [NSImage], topStaticHeight: Int, bottomStaticHeight: Int) {
    let contentHeight = frameHeight - topStaticHeight - bottomStaticHeight
    let fullContentHeight = contentHeight + max(0, frameCount - 1) * (contentHeight - overlapRows)
    let fullContent = makeUniqueRowImage(width: width, height: fullContentHeight)
    var frames: [NSImage] = []
    for idx in 0..<frameCount {
        let y = idx * (contentHeight - overlapRows)
        let contentSlice = cropNSImage(
            fullContent,
            to: CGRect(x: 0, y: y, width: width, height: contentHeight)
        )
        let composed = NSImage(size: NSSize(width: width, height: frameHeight))
        composed.lockFocus()
        NSColor(white: 0.88, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: frameHeight - topStaticHeight, width: width, height: topStaticHeight)).fill()
        contentSlice.draw(in: NSRect(x: 0, y: bottomStaticHeight, width: width, height: contentHeight))
        NSColor(white: 0.83, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: bottomStaticHeight)).fill()
        composed.unlockFocus()
        frames.append(composed)
    }
    return (frames, topStaticHeight, bottomStaticHeight)
}

func makeFramesWithScrollbar(
    width: Int,
    frameHeight: Int,
    scrollbarWidth: Int,
    overlapRows: Int,
    frameCount: Int
) -> (frames: [NSImage], scrollbarWidth: Int) {
    let (contentFrames, _) = makeScrollingFrames(
        width: width - scrollbarWidth,
        frameHeight: frameHeight,
        overlapRows: overlapRows,
        frameCount: frameCount
    )
    var frames: [NSImage] = []
    for idx in 0..<contentFrames.count {
        let image = NSImage(size: NSSize(width: width, height: frameHeight))
        image.lockFocus()
        contentFrames[idx].draw(in: NSRect(x: 0, y: 0, width: width - scrollbarWidth, height: frameHeight))
        let hue = CGFloat((idx * 37) % 255) / 255.0
        NSColor(calibratedHue: hue, saturation: 0.6, brightness: 0.9, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(
            x: width - scrollbarWidth,
            y: 0,
            width: scrollbarWidth,
            height: frameHeight
        )).fill()
        image.unlockFocus()
        frames.append(image)
    }
    return (frames, scrollbarWidth)
}
