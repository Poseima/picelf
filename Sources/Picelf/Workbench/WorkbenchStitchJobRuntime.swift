import AppKit

@MainActor
protocol WorkbenchStitchJobRuntime: AnyObject {
    func stitch(onProgress: ((StitchingProgress) -> Void)?) async throws -> NSImage
    func cancel()
    func reset()
    var outputFileURL: URL? { get }
}

extension WorkbenchStitchJobRuntime {
    var outputFileURL: URL? { nil }
}

extension StitchingCoordinator: WorkbenchStitchJobRuntime {}
