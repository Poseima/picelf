import Foundation

extension E2EValidationReport {
    func formattedSummary(prefix: String) -> String {
        var lines: [String] = []
        lines.append("\(prefix) Validation result: \(passed ? "PASS" : "FAIL")")

        var statsParts: [String] = []
        if let contrast = stats.contrast {
            statsParts.append("contrast=\(contrast)")
        }
        if let overlapRatio = stats.overlapRatio {
            statsParts.append("overlap=\(String(format: "%.1f%%", overlapRatio * 100))")
        }
        statsParts.append("duplicateRuns=\(stats.duplicateRunCount)")
        statsParts.append("seams=\(stats.seamCount)")
        statsParts.append("repeatedSections=\(stats.repeatedSectionCount)")
        statsParts.append("edgeOverlayRepeats=\(stats.edgeOverlayRepeatCount)")
        statsParts.append("duplicatedArea=\(String(format: "%.1f%%", stats.duplicatedAreaRatio * 100))")
        lines.append("\(prefix) Stats: \(statsParts.joined(separator: ", "))")

        for check in checks {
            lines.append("\(prefix) [\(check.passed ? "PASS" : "FAIL")] \(check.name): \(check.detail)")
        }

        if issues.isEmpty {
            lines.append("\(prefix) Issues: none")
        } else {
            lines.append("\(prefix) Issues (\(issues.count)):")
            for issue in issues.prefix(10) {
                var loc = ""
                if let yStart = issue.yStart, let yEnd = issue.yEnd {
                    loc += " y=\(yStart)-\(yEnd)"
                }
                if let offset = issue.offsetPx {
                    loc += " offset=\(offset)"
                }
                lines.append("\(prefix) - [\(issue.severity.rawValue)] \(issue.category): \(issue.message)\(loc)")
            }
            if issues.count > 10 {
                lines.append("\(prefix) - ... \(issues.count - 10) more")
            }
        }

        return lines.joined(separator: "\n")
    }

    func failureSummary(prefix: String) -> String {
        guard !passed else { return "" }

        var parts: [String] = []
        for check in checks where !check.passed {
            parts.append("\(check.name): \(check.detail)")
        }

        let blockingIssues = issues.filter { policy.blocks($0.severity) }
        for issue in blockingIssues.prefix(8) {
            var loc = ""
            if let yStart = issue.yStart, let yEnd = issue.yEnd {
                loc += " y=\(yStart)-\(yEnd)"
            }
            if let offset = issue.offsetPx {
                loc += " offset=\(offset)"
            }
            parts.append("\(issue.category): \(issue.message)\(loc)")
        }

        if parts.isEmpty {
            parts.append("Unknown validation failure")
        }

        return "\(prefix) Validation failed: " + parts.joined(separator: " | ")
    }
}
