import CoreGraphics
import Foundation

enum E2EStitchValidator {

    static func validateStitchedImage(
        _ image: CGImage,
        context: E2EValidationContext,
        profile: E2EValidationProfile = .highRecall,
        policy: E2EValidationPolicy = .criticalOnly
    ) -> E2EValidationReport {
        var checks: [E2EValidationCheck] = []
        var issues: [E2EValidationIssue] = []
        var stats = E2EValidationStats()

        guard let gray = makeGrayscaleImage(image) else {
            checks.append(E2EValidationCheck(
                name: "Grayscale conversion",
                passed: false,
                detail: "Failed to convert image to grayscale buffer"
            ))
            issues.append(E2EValidationIssue(
                category: "pipeline",
                severity: .critical,
                message: "Could not analyze image pixels",
                yStart: nil,
                yEnd: nil,
                offsetPx: nil
            ))
            return E2EValidationReport(checks: checks, issues: issues, stats: stats, policy: policy)
        }

        if let windowPixelWidth = context.windowPixelWidth {
            // Edge cropping can happen on both left and right sides.
            // profile.maxEdgeCrop is interpreted as per-side allowance.
            let maxTotalEdgeCrop = profile.maxEdgeCrop * 2
            let minExpectedWidth = max(1, windowPixelWidth - maxTotalEdgeCrop)
            let passed = image.width >= minExpectedWidth
            checks.append(E2EValidationCheck(
                name: "Retina width",
                passed: passed,
                detail: "actual=\(image.width), expected>=\(minExpectedWidth), window=\(windowPixelWidth), maxEdgeCropPerSide=\(profile.maxEdgeCrop)"
            ))
        }

        if let windowPixelHeight = context.windowPixelHeight {
            let tallEnough = image.height > windowPixelHeight
            checks.append(E2EValidationCheck(
                name: "Long screenshot",
                passed: tallEnough,
                detail: "actual=\(image.height), windowHeight=\(windowPixelHeight)"
            ))

            if profile.requireTallerThanWide {
                let tallerThanWide = image.height > image.width
                checks.append(E2EValidationCheck(
                    name: "Taller than wide",
                    passed: tallerThanWide,
                    detail: "size=\(image.width)x\(image.height)"
                ))
            }

            if let acceptedFrames = context.acceptedFrameCount, acceptedFrames > 0 {
                let naiveConcatHeight = acceptedFrames * windowPixelHeight
                let lessThanNaive = image.height < naiveConcatHeight
                checks.append(E2EValidationCheck(
                    name: "Naive concat guard",
                    passed: lessThanNaive,
                    detail: "stitched=\(image.height), naive=\(naiveConcatHeight), acceptedFrames=\(acceptedFrames)"
                ))

                if naiveConcatHeight > 0 {
                    let overlapRatio = 1.0 - Double(image.height) / Double(naiveConcatHeight)
                    stats.overlapRatio = overlapRatio
                    let overlapPass = overlapRatio > profile.minOverlapRatio
                    checks.append(E2EValidationCheck(
                        name: "Overlap removal",
                        passed: overlapPass,
                        detail: "ratio=\(String(format: "%.3f", overlapRatio)), min=\(String(format: "%.3f", profile.minOverlapRatio))"
                    ))
                }
            }
        }

        if let sampledContrast = contrast(in: gray, rect: context.contrastSampleRect) {
            stats.contrast = sampledContrast
            let contrastPass = sampledContrast > profile.minContrast
            checks.append(E2EValidationCheck(
                name: "Text contrast",
                passed: contrastPass,
                detail: "contrast=\(sampledContrast), min=\(profile.minContrast)"
            ))
        } else {
            checks.append(E2EValidationCheck(
                name: "Text contrast",
                passed: false,
                detail: "Contrast sample rect was outside image bounds"
            ))
        }

        let artifactResult = detectArtifacts(in: gray, profile: profile)
        issues.append(contentsOf: artifactResult.issues)
        stats.duplicateRunCount = artifactResult.duplicateRunCount
        stats.seamCount = artifactResult.seamCount
        stats.repeatedSectionCount = artifactResult.repeatedSectionCount
        stats.edgeOverlayRepeatCount = artifactResult.edgeOverlayRepeatCount
        stats.duplicatedAreaRatio = artifactResult.duplicatedAreaRatio

        let blockingIssues = issues.filter { policy.blocks($0.severity) }
        let warningIssues = issues.filter { $0.severity == .warning }
        checks.append(E2EValidationCheck(
            name: "Artifact scan",
            passed: blockingIssues.isEmpty,
            detail: "critical=\(issues.filter { $0.severity == .critical }.count), warning=\(warningIssues.count), blocking=\(blockingIssues.count), duplicateRuns=\(stats.duplicateRunCount), seams=\(stats.seamCount), repeatedSections=\(stats.repeatedSectionCount), edgeOverlayRepeats=\(stats.edgeOverlayRepeatCount), duplicatedAreaRatio=\(String(format: "%.3f", stats.duplicatedAreaRatio))"
        ))

        return E2EValidationReport(checks: checks, issues: issues, stats: stats, policy: policy)
    }

    // MARK: - Artifact Detection

    private static func detectArtifacts(
        in gray: GrayscaleImage,
        profile: E2EValidationProfile
    ) -> ArtifactResult {
        let duplication = detectDuplicateRuns(in: gray, rules: profile.duplicationRules)
        let seams = detectSeams(in: gray, rules: profile.seamRules)
        let repeated = detectRepeatedSections(in: gray, rules: profile.repeatedSectionRules)
        let edgeOverlays = detectEdgeOverlayRepeats(in: gray, rules: profile.edgeOverlayRules)

        var issues: [E2EValidationIssue] = []
        issues.append(contentsOf: duplication.issues)
        issues.append(contentsOf: seams.issues)
        issues.append(contentsOf: repeated.issues)
        issues.append(contentsOf: edgeOverlays.issues)

        // Duplicated-area ratio tracks broad content duplication artifacts.
        // Edge-overlay issues are narrow-strip phenomena and should not inflate
        // full-row coverage metrics.
        var rowMask = [Bool](repeating: false, count: gray.height)
        for interval in duplication.rowIntervals + seams.rowIntervals + repeated.rowIntervals {
            let start = max(0, min(gray.height, interval.start))
            let end = max(start, min(gray.height, interval.end))
            if start < end {
                for row in start..<end {
                    rowMask[row] = true
                }
            }
        }

        let duplicatedRows = rowMask.reduce(0) { $1 ? $0 + 1 : $0 }
        let duplicatedAreaRatio = gray.height > 0
            ? Double(duplicatedRows) / Double(gray.height)
            : 0

        if duplicatedAreaRatio >= profile.duplicationRules.criticalAreaRatio {
            issues.append(E2EValidationIssue(
                category: "duplication",
                severity: .critical,
                message: "Duplicated area ratio \(String(format: "%.1f%%", duplicatedAreaRatio * 100)) exceeds \(String(format: "%.1f%%", profile.duplicationRules.criticalAreaRatio * 100))",
                yStart: nil,
                yEnd: nil,
                offsetPx: nil
            ))
        }

        return ArtifactResult(
            issues: issues,
            duplicateRunCount: duplication.issues.count,
            seamCount: seams.issues.count,
            repeatedSectionCount: repeated.issues.count,
            edgeOverlayRepeatCount: edgeOverlays.issues.count,
            duplicatedAreaRatio: duplicatedAreaRatio
        )
    }

    private static func detectDuplicateRuns(
        in gray: GrayscaleImage,
        rules: DuplicationRules
    ) -> DetectorOutput {
        let w = gray.width
        let h = gray.height
        let blockHeight = max(8, rules.blockHeight)
        let blockCount = h / blockHeight
        guard blockCount >= max(rules.criticalHighRunLength + 1, 4) else {
            return DetectorOutput.empty
        }

        let bins = max(8, rules.fingerprintBins)
        let binWidth = max(1, w / bins)

        struct BlockInfo {
            let fingerprint: [Float]
            let isContent: Bool
        }

        var blocks: [BlockInfo] = []
        blocks.reserveCapacity(blockCount)

        for block in 0..<blockCount {
            let startRow = block * blockHeight
            let endRow = min(startRow + blockHeight, h)

            var sums = [Float](repeating: 0, count: bins)
            var counts = [Int](repeating: 0, count: bins)
            var minVal: UInt8 = 255
            var maxVal: UInt8 = 0
            var sum: Float = 0
            var sumSquares: Float = 0
            var sampleCount = 0

            for row in stride(from: startRow, to: endRow, by: 2) {
                let rowStart = row * w
                for bin in 0..<bins {
                    let colStart = bin * binWidth
                    let colEnd = (bin == bins - 1) ? w : min(w, colStart + binWidth)
                    for col in stride(from: colStart, to: colEnd, by: 4) {
                        let value = gray.pixels[rowStart + col]
                        sums[bin] += Float(value)
                        counts[bin] += 1
                        if value < minVal { minVal = value }
                        if value > maxVal { maxVal = value }
                        let fv = Float(value)
                        sum += fv
                        sumSquares += fv * fv
                        sampleCount += 1
                    }
                }
            }

            var fingerprint = [Float](repeating: 0, count: bins)
            for i in 0..<bins {
                fingerprint[i] = counts[i] > 0 ? sums[i] / Float(counts[i]) : 0
            }

            let dynamicRange = maxVal &- minVal
            let stdDev: Float
            if sampleCount > 0 {
                let invN = 1.0 / Float(sampleCount)
                let mean = sum * invN
                stdDev = sqrt(max(0, sumSquares * invN - mean * mean))
            } else {
                stdDev = 0
            }
            let isContent = dynamicRange >= rules.contentRangeFloor
                && stdDev >= rules.contentStdDevFloor
            blocks.append(BlockInfo(fingerprint: fingerprint, isContent: isContent))
        }

        let minOffsetBlocks = max(1, (rules.minOffsetPx + blockHeight - 1) / blockHeight)
        let maxOffsetBlocks = min(blockCount - 1, max(1, rules.maxOffsetPx / blockHeight))
        guard minOffsetBlocks <= maxOffsetBlocks else {
            return DetectorOutput.empty
        }

        var issues: [E2EValidationIssue] = []
        var rowIntervals: [RowInterval] = []

        for offset in minOffsetBlocks...maxOffsetBlocks {
            var runLength = 0
            var runStart = 0
            var corrSum: Float = 0

            func finalizeRun() {
                guard runLength > 0 else {
                    runLength = 0
                    corrSum = 0
                    return
                }

                let averageCorrelation = corrSum / Float(runLength)

                if runLength >= rules.warningRunLength {
                    var mads: [Float] = []
                    mads.reserveCapacity(runLength)
                    for step in 0..<runLength {
                        let rowA = (runStart + step) * blockHeight
                        let rowB = (runStart + step + offset) * blockHeight
                        let comparedHeight = min(blockHeight, h - max(rowA, rowB))
                        guard comparedHeight > 0 else { continue }
                        let mad = pixelMAD(
                            gray,
                            rowA: rowA,
                            rowB: rowB,
                            regionHeight: comparedHeight,
                            sampleStrideY: 2,
                            sampleStrideX: 4
                        )
                        mads.append(mad)
                    }

                    if !mads.isEmpty {
                        mads.sort()
                        let medianMAD = mads[mads.count / 2]

                        let highRule = runLength >= rules.criticalHighRunLength
                            && averageCorrelation >= rules.criticalHighAverageCorrelation
                            && medianMAD <= rules.criticalHighMedianMAD

                        let lowRule = runLength >= rules.criticalLowRunLength
                            && averageCorrelation >= rules.criticalLowAverageCorrelation
                            && medianMAD <= rules.criticalLowMedianMAD

                        let warningStrictRule = runLength >= rules.warningRunLength
                            && averageCorrelation >= rules.warningAverageCorrelation
                            && medianMAD <= rules.warningMedianMAD

                        let warningLayoutRule = runLength >= rules.layoutWarningRunLength
                            && averageCorrelation >= rules.layoutWarningAverageCorrelation
                            && medianMAD <= rules.layoutWarningMedianMAD

                        let severity: E2EValidationSeverity?
                        if highRule || lowRule {
                            severity = .critical
                        } else if warningStrictRule || warningLayoutRule {
                            severity = .warning
                        } else {
                            severity = nil
                        }

                        if let severity {
                            let startA = runStart * blockHeight
                            let endA = min(h, startA + runLength * blockHeight)
                            let startB = (runStart + offset) * blockHeight
                            let endB = min(h, startB + runLength * blockHeight)
                            let offsetPx = offset * blockHeight

                            issues.append(E2EValidationIssue(
                                category: "duplication",
                                severity: severity,
                                message: "Consecutive duplicate run \(runLength) blocks (corr=\(String(format: "%.3f", averageCorrelation)), medianMAD=\(String(format: "%.1f", medianMAD)))",
                                yStart: min(startA, startB),
                                yEnd: max(endA, endB),
                                offsetPx: offsetPx
                            ))

                            if severity == .critical {
                                rowIntervals.append(RowInterval(start: startA, end: endA))
                                rowIntervals.append(RowInterval(start: startB, end: endB))
                            }
                        }
                    }
                }

                runLength = 0
                corrSum = 0
            }

            for index in 0..<(blockCount - offset) {
                let target = index + offset
                guard blocks[index].isContent && blocks[target].isContent else {
                    finalizeRun()
                    continue
                }

                let corr = pearsonCorrelation(blocks[index].fingerprint, blocks[target].fingerprint)
                if corr >= rules.baseCorrelationThreshold {
                    if runLength == 0 { runStart = index }
                    runLength += 1
                    corrSum += corr
                } else {
                    finalizeRun()
                }
            }

            finalizeRun()

            if issues.count >= 40 {
                break
            }
        }

        return DetectorOutput(issues: issues, rowIntervals: rowIntervals)
    }

    private static func detectSeams(
        in gray: GrayscaleImage,
        rules: SeamRules
    ) -> DetectorOutput {
        let w = gray.width
        let h = gray.height
        let bandHeight = max(4, rules.bandHeight)
        let bandCount = h / bandHeight
        guard bandCount > 2 else { return DetectorOutput.empty }

        let minOffsetBands = max(1, (rules.minOffsetPx + bandHeight - 1) / bandHeight)
        let maxOffsetBands = min(bandCount - 1, max(1, rules.maxOffsetPx / bandHeight))
        guard minOffsetBands <= maxOffsetBands else { return DetectorOutput.empty }

        func bandMAD(rowA: Int, rowB: Int) -> (mad: Float, isContent: Bool) {
            var totalDiff: Float = 0
            var count = 0
            var samples: [UInt8] = []
            var sum: Float = 0
            var sumSquares: Float = 0

            for row in stride(from: 0, to: bandHeight, by: 4) {
                let a = rowA + row
                let b = rowB + row
                guard a < h, b < h else { break }
                let offsetA = a * w
                let offsetB = b * w
                for col in stride(from: 0, to: w, by: 8) {
                    let va = gray.pixels[offsetA + col]
                    let vb = gray.pixels[offsetB + col]
                    totalDiff += abs(Float(va) - Float(vb))
                    count += 1
                    samples.append(va)
                    let fv = Float(va)
                    sum += fv
                    sumSquares += fv * fv
                }
            }

            let mad = count > 0 ? totalDiff / Float(count) : Float.infinity
            let n = samples.count
            guard n >= 4 else { return (mad: mad, isContent: false) }

            // Use IQR instead of full range to avoid false positives from
            // consistent borders/sidebars inflating range of uniform regions
            // (e.g., white PDF page space with a thin dark page border)
            samples.sort()
            let iqr = samples[n * 3 / 4] &- samples[n / 4]

            let invN = 1.0 / Float(n)
            let mean = sum * invN
            let stdDev = sqrt(max(0, sumSquares * invN - mean * mean))

            let isContent = iqr >= rules.contentRangeFloor
                && stdDev >= rules.contentStdDevFloor
            return (mad: mad, isContent: isContent)
        }

        var issues: [E2EValidationIssue] = []
        var intervals: [RowInterval] = []

        for offsetBands in minOffsetBands...maxOffsetBands {
            let offsetPx = offsetBands * bandHeight
            var runBands = 0
            var runStartBand = 0
            var madSum: Float = 0

            func finalizeRun() {
                guard runBands > 0 else {
                    runBands = 0
                    madSum = 0
                    return
                }

                let runHeight = runBands * bandHeight
                let requiredHeight = max(
                    rules.minRunHeightPx,
                    Int(Float(offsetPx) * rules.offsetRunMultiplier)
                )

                if runHeight >= requiredHeight && runHeight <= rules.maxRunHeightPx {
                    let avgMAD = madSum / Float(runBands)
                    let startRowA = runStartBand * bandHeight
                    let endRowA = min(h, startRowA + runHeight)
                    let startRowB = startRowA + offsetPx
                    let endRowB = min(h, startRowB + runHeight)

                    let criticalRule = runHeight >= max(requiredHeight, rules.criticalMinRunHeightPx)
                        && avgMAD <= rules.criticalMaxBandMAD
                    let warningRule = avgMAD <= rules.warningMaxBandMAD

                    if criticalRule || warningRule {
                        let severity: E2EValidationSeverity = criticalRule ? .critical : .warning
                        issues.append(E2EValidationIssue(
                            category: "seam",
                            severity: severity,
                            message: "Seam-like duplicated band height=\(runHeight)px, offset=\(offsetPx)px, avgMAD=\(String(format: "%.2f", avgMAD))",
                            yStart: min(startRowA, startRowB),
                            yEnd: max(endRowA, endRowB),
                            offsetPx: offsetPx
                        ))

                        if severity == .critical {
                            intervals.append(RowInterval(start: startRowA, end: endRowA))
                            intervals.append(RowInterval(start: startRowB, end: endRowB))
                        }
                    }
                }

                runBands = 0
                madSum = 0
            }

            for band in 0..<(bandCount - offsetBands) {
                let rowA = band * bandHeight
                let rowB = (band + offsetBands) * bandHeight
                let comparison = bandMAD(rowA: rowA, rowB: rowB)
                if comparison.mad <= rules.warningMaxBandMAD && comparison.isContent {
                    if runBands == 0 { runStartBand = band }
                    runBands += 1
                    madSum += comparison.mad
                } else {
                    finalizeRun()
                }
            }

            finalizeRun()

            if issues.count >= 40 { break }
        }

        return DetectorOutput(issues: issues, rowIntervals: intervals)
    }

    private static func detectRepeatedSections(
        in gray: GrayscaleImage,
        rules: RepeatedSectionRules
    ) -> DetectorOutput {
        let w = gray.width
        let h = gray.height
        let windowHeight = max(32, rules.windowHeight)
        let windowStride = max(8, rules.windowStride)
        guard h >= windowHeight else { return DetectorOutput.empty }

        let bins = max(8, rules.fingerprintBins)
        let binWidth = max(1, w / bins)

        struct SectionInfo {
            let startRow: Int
            let fingerprint: [Float]
            let isContent: Bool
        }

        var sections: [SectionInfo] = []
        for startRow in stride(from: 0, through: h - windowHeight, by: windowStride) {
            var sums = [Float](repeating: 0, count: bins)
            var counts = [Int](repeating: 0, count: bins)
            var minVal: UInt8 = 255
            var maxVal: UInt8 = 0
            var sum: Float = 0
            var sumSquares: Float = 0
            var sampleCount = 0

            for row in stride(from: startRow, to: startRow + windowHeight, by: 4) {
                let rowStart = row * w
                for bin in 0..<bins {
                    let colStart = bin * binWidth
                    let colEnd = (bin == bins - 1) ? w : min(w, colStart + binWidth)
                    for col in stride(from: colStart, to: colEnd, by: 4) {
                        let value = gray.pixels[rowStart + col]
                        sums[bin] += Float(value)
                        counts[bin] += 1
                        if value < minVal { minVal = value }
                        if value > maxVal { maxVal = value }
                        let fv = Float(value)
                        sum += fv
                        sumSquares += fv * fv
                        sampleCount += 1
                    }
                }
            }

            var fingerprint = [Float](repeating: 0, count: bins)
            for index in 0..<bins {
                fingerprint[index] = counts[index] > 0 ? sums[index] / Float(counts[index]) : 0
            }

            let dynamicRange = maxVal &- minVal
            let stdDev: Float
            if sampleCount > 0 {
                let invN = 1.0 / Float(sampleCount)
                let mean = sum * invN
                stdDev = sqrt(max(0, sumSquares * invN - mean * mean))
            } else {
                stdDev = 0
            }

            let isContent = dynamicRange >= rules.contentRangeFloor
                && stdDev >= rules.contentStdDevFloor
            sections.append(SectionInfo(startRow: startRow, fingerprint: fingerprint, isContent: isContent))
        }

        let sectionCount = sections.count
        guard sectionCount > rules.minConsecutiveWindows else { return DetectorOutput.empty }

        let minOffsetSections = max(1, (rules.minOffsetPx + windowStride - 1) / windowStride)
        let maxOffsetSections = min(sectionCount - 1, max(1, rules.maxOffsetPx / windowStride))
        guard minOffsetSections <= maxOffsetSections else { return DetectorOutput.empty }

        var issues: [E2EValidationIssue] = []
        var intervals: [RowInterval] = []

        for offset in minOffsetSections...maxOffsetSections {
            var runLength = 0
            var runStart = 0

            func finalizeRun() {
                guard runLength >= rules.minConsecutiveWindows else {
                    runLength = 0
                    return
                }

                var mads: [Float] = []
                mads.reserveCapacity(runLength)
                for step in 0..<runLength {
                    let first = sections[runStart + step]
                    let second = sections[runStart + step + offset]
                    let mad = pixelMAD(
                        gray,
                        rowA: first.startRow,
                        rowB: second.startRow,
                        regionHeight: windowHeight,
                        sampleStrideY: 4,
                        sampleStrideX: 4
                    )
                    mads.append(mad)
                }

                if !mads.isEmpty {
                    mads.sort()
                    let medianMAD = mads[mads.count / 2]
                    let criticalRule = runLength >= rules.criticalMinConsecutiveWindows
                        && medianMAD <= rules.criticalMaxPixelMAD
                    let warningRule = medianMAD <= rules.warningMaxPixelMAD

                    if criticalRule || warningRule {
                        let startA = sections[runStart].startRow
                        let endA = min(h, startA + runLength * windowStride + windowHeight)
                        let startB = sections[runStart + offset].startRow
                        let endB = min(h, startB + runLength * windowStride + windowHeight)
                        let severity: E2EValidationSeverity = criticalRule ? .critical : .warning

                        issues.append(E2EValidationIssue(
                            category: "repeated-section",
                            severity: severity,
                            message: "Repeated section run \(runLength) windows (medianMAD=\(String(format: "%.1f", medianMAD)))",
                            yStart: min(startA, startB),
                            yEnd: max(endA, endB),
                            offsetPx: (startB - startA)
                        ))

                        if severity == .critical {
                            intervals.append(RowInterval(start: startA, end: endA))
                            intervals.append(RowInterval(start: startB, end: endB))
                        }
                    }
                }

                runLength = 0
            }

            for index in 0..<(sectionCount - offset) {
                let other = index + offset
                let first = sections[index]
                let second = sections[other]
                guard first.isContent && second.isContent else {
                    finalizeRun()
                    continue
                }

                let mad = fingerprintMAD(first.fingerprint, second.fingerprint)
                if mad <= rules.maxFingerprintMAD {
                    if runLength == 0 { runStart = index }
                    runLength += 1
                } else {
                    finalizeRun()
                }
            }

            finalizeRun()

            if issues.count >= 40 { break }
        }

        return DetectorOutput(issues: issues, rowIntervals: intervals)
    }

    private static func detectEdgeOverlayRepeats(
        in gray: GrayscaleImage,
        rules: EdgeOverlayRules
    ) -> DetectorOutput {
        guard rules.enabled else { return .empty }

        let w = gray.width
        let h = gray.height
        let stripWidth = min(max(24, rules.stripWidth), max(24, w / 3))
        let windowHeight = max(48, rules.windowHeight)
        let windowStride = max(16, rules.windowStride)
        guard h >= windowHeight * 3, w > stripWidth + 32 else { return .empty }

        let windowCount = ((h - windowHeight) / windowStride) + 1
        guard windowCount > max(2, rules.warningMinMatches) else { return .empty }

        struct EdgeWindowInfo {
            let startRow: Int
            let isFeatureRich: Bool
        }

        let rightX = w - stripWidth
        let centerWidth = max(64, w - stripWidth - 24)

        var windows: [EdgeWindowInfo] = []
        windows.reserveCapacity(windowCount)

        for index in 0..<windowCount {
            let startRow = index * windowStride
            let endRow = startRow + windowHeight

            var minValue: UInt8 = 255
            var maxValue: UInt8 = 0
            var sum: Float = 0
            var sumSquares: Float = 0
            var darkCount = 0
            var sampleCount = 0

            for row in stride(from: startRow, to: endRow, by: 3) {
                let rowStart = row * w
                for col in stride(from: rightX, to: w, by: 2) {
                    let value = gray.pixels[rowStart + col]
                    if value < minValue { minValue = value }
                    if value > maxValue { maxValue = value }
                    if value <= rules.darkPixelThreshold { darkCount += 1 }

                    let fv = Float(value)
                    sum += fv
                    sumSquares += fv * fv
                    sampleCount += 1
                }
            }

            let dynamicRange = maxValue &- minValue
            let stdDev: Float
            if sampleCount > 0 {
                let invN = 1.0 / Float(sampleCount)
                let mean = sum * invN
                stdDev = sqrt(max(0, sumSquares * invN - mean * mean))
            } else {
                stdDev = 0
            }

            let darkRatio = sampleCount > 0 ? Float(darkCount) / Float(sampleCount) : 0
            let isFeatureRich = dynamicRange >= rules.minFeatureRange
                && stdDev >= rules.minFeatureStdDev
                && darkRatio >= rules.minFeatureDarkRatio
                && darkRatio <= rules.maxFeatureDarkRatio

            windows.append(EdgeWindowInfo(startRow: startRow, isFeatureRich: isFeatureRich))
        }

        let featureWindowCount = windows.reduce(0) { partial, window in
            partial + (window.isFeatureRich ? 1 : 0)
        }
        guard featureWindowCount >= max(rules.warningMinMatches, 3) else {
            return .empty
        }

        let minOffsetWindows = max(1, (rules.minOffsetPx + windowStride - 1) / windowStride)
        let maxOffsetWindows = min(windowCount - 1, max(1, rules.maxOffsetPx / windowStride))
        guard minOffsetWindows <= maxOffsetWindows else { return .empty }

        var issues: [E2EValidationIssue] = []
        var intervals: [RowInterval] = []

        for offset in minOffsetWindows...maxOffsetWindows {
            var matchPairs: [(startA: Int, startB: Int, stripMAD: Float, centerMAD: Float)] = []
            matchPairs.reserveCapacity(windowCount / 2)
            var matchedRows = Set<Int>()

            for index in 0..<(windowCount - offset) {
                let first = windows[index]
                let second = windows[index + offset]
                guard first.isFeatureRich && second.isFeatureRich else { continue }

                let stripMAD = pixelMADInRect(
                    gray,
                    rowA: first.startRow,
                    rowB: second.startRow,
                    regionHeight: windowHeight,
                    xStart: rightX,
                    regionWidth: stripWidth,
                    sampleStrideY: 3,
                    sampleStrideX: 2
                )

                guard stripMAD <= rules.maxStripMAD else { continue }

                let centerMAD = pixelMADInRect(
                    gray,
                    rowA: first.startRow,
                    rowB: second.startRow,
                    regionHeight: windowHeight,
                    xStart: 0,
                    regionWidth: centerWidth,
                    sampleStrideY: 4,
                    sampleStrideX: 6
                )

                guard centerMAD >= rules.minCenterMAD,
                      centerMAD >= stripMAD * rules.minCenterToStripMADRatio else {
                    continue
                }

                matchPairs.append((
                    startA: first.startRow,
                    startB: second.startRow,
                    stripMAD: stripMAD,
                    centerMAD: centerMAD
                ))
                matchedRows.insert(first.startRow)
                matchedRows.insert(second.startRow)
            }

            guard matchPairs.count >= rules.warningMinMatches else { continue }
            let coverage = Float(matchedRows.count) / Float(featureWindowCount)
            guard coverage <= rules.maxMatchedWindowCoverage else { continue }

            let severity: E2EValidationSeverity = matchPairs.count >= rules.criticalMinMatches ? .critical : .warning
            let startRowsA = matchPairs.map { $0.startA }
            let startRowsB = matchPairs.map { $0.startB }
            let yStart = min(startRowsA.min() ?? 0, startRowsB.min() ?? 0)
            let yEnd = max((startRowsA.max() ?? 0) + windowHeight, (startRowsB.max() ?? 0) + windowHeight)

            let sortedStripMAD = matchPairs.map { $0.stripMAD }.sorted()
            let sortedCenterMAD = matchPairs.map { $0.centerMAD }.sorted()
            let medianStripMAD = sortedStripMAD[sortedStripMAD.count / 2]
            let medianCenterMAD = sortedCenterMAD[sortedCenterMAD.count / 2]

            issues.append(E2EValidationIssue(
                category: "edge-overlay",
                severity: severity,
                message: "Repeated right-edge overlay matches=\(matchPairs.count) coverage=\(String(format: "%.2f", coverage)) (medianStripMAD=\(String(format: "%.1f", medianStripMAD)), medianCenterMAD=\(String(format: "%.1f", medianCenterMAD)))",
                yStart: yStart,
                yEnd: yEnd,
                offsetPx: offset * windowStride
            ))

            if severity == .critical {
                intervals.append(RowInterval(start: yStart, end: yEnd))
            }

            if issues.count >= 20 { break }
        }

        return DetectorOutput(issues: issues, rowIntervals: intervals)
    }

    // MARK: - Numeric Helpers

    private static func contrast(in gray: GrayscaleImage, rect: CGRect) -> Int? {
        let imageRect = CGRect(x: 0, y: 0, width: gray.width, height: gray.height)
        let clipped = rect.intersection(imageRect).integral
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else {
            return nil
        }

        let minX = max(0, min(gray.width - 1, Int(clipped.minX)))
        let maxX = max(minX + 1, min(gray.width, Int(clipped.maxX)))
        let minY = max(0, min(gray.height - 1, Int(clipped.minY)))
        let maxY = max(minY + 1, min(gray.height, Int(clipped.maxY)))

        var minValue: UInt8 = 255
        var maxValue: UInt8 = 0

        for row in minY..<maxY {
            let rowStart = row * gray.width
            for col in minX..<maxX {
                let value = gray.pixels[rowStart + col]
                if value < minValue { minValue = value }
                if value > maxValue { maxValue = value }
            }
        }

        return Int(maxValue) - Int(minValue)
    }

    private static func pearsonCorrelation(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        let count = Float(a.count)
        let meanA = a.reduce(0, +) / count
        let meanB = b.reduce(0, +) / count

        var covariance: Float = 0
        var varianceA: Float = 0
        var varianceB: Float = 0

        for i in 0..<a.count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            covariance += da * db
            varianceA += da * da
            varianceB += db * db
        }

        let denominator = sqrt(varianceA * varianceB)
        return denominator > 1e-6 ? covariance / denominator : 0
    }

    private static func fingerprintMAD(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return Float.infinity }
        var total: Float = 0
        for i in 0..<a.count {
            total += abs(a[i] - b[i])
        }
        return total / Float(a.count)
    }

    private static func pixelMAD(
        _ gray: GrayscaleImage,
        rowA: Int,
        rowB: Int,
        regionHeight: Int,
        sampleStrideY: Int,
        sampleStrideX: Int
    ) -> Float {
        let h = gray.height
        let w = gray.width
        guard rowA >= 0, rowB >= 0, regionHeight > 0 else { return Float.infinity }

        var totalDiff: Float = 0
        var count = 0

        for delta in stride(from: 0, to: regionHeight, by: max(1, sampleStrideY)) {
            let a = rowA + delta
            let b = rowB + delta
            guard a < h, b < h else { break }

            let rowOffsetA = a * w
            let rowOffsetB = b * w

            for col in stride(from: 0, to: w, by: max(1, sampleStrideX)) {
                totalDiff += abs(Float(gray.pixels[rowOffsetA + col]) - Float(gray.pixels[rowOffsetB + col]))
                count += 1
            }
        }

        return count > 0 ? totalDiff / Float(count) : Float.infinity
    }

    private static func pixelMADInRect(
        _ gray: GrayscaleImage,
        rowA: Int,
        rowB: Int,
        regionHeight: Int,
        xStart: Int,
        regionWidth: Int,
        sampleStrideY: Int,
        sampleStrideX: Int
    ) -> Float {
        let h = gray.height
        let w = gray.width
        guard rowA >= 0, rowB >= 0, regionHeight > 0, regionWidth > 0 else {
            return Float.infinity
        }

        let minX = max(0, xStart)
        let maxX = min(w, minX + regionWidth)
        guard minX < maxX else { return Float.infinity }

        var totalDiff: Float = 0
        var count = 0

        for delta in stride(from: 0, to: regionHeight, by: max(1, sampleStrideY)) {
            let a = rowA + delta
            let b = rowB + delta
            guard a < h, b < h else { break }

            let rowOffsetA = a * w
            let rowOffsetB = b * w

            for col in stride(from: minX, to: maxX, by: max(1, sampleStrideX)) {
                totalDiff += abs(Float(gray.pixels[rowOffsetA + col]) - Float(gray.pixels[rowOffsetB + col]))
                count += 1
            }
        }

        return count > 0 ? totalDiff / Float(count) : Float.infinity
    }

    // MARK: - Pixel Buffer

    private static func makeGrayscaleImage(_ image: CGImage) -> GrayscaleImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpace(name: CGColorSpace.linearGray)!,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return GrayscaleImage(width: width, height: height, pixels: pixels)
    }
}

private struct GrayscaleImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}

private struct RowInterval {
    let start: Int
    let end: Int
}

private struct DetectorOutput {
    let issues: [E2EValidationIssue]
    let rowIntervals: [RowInterval]

    static let empty = DetectorOutput(issues: [], rowIntervals: [])
}

private struct ArtifactResult {
    let issues: [E2EValidationIssue]
    let duplicateRunCount: Int
    let seamCount: Int
    let repeatedSectionCount: Int
    let edgeOverlayRepeatCount: Int
    let duplicatedAreaRatio: Double
}
