import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let sendToIPad = Self("sendToIPad", default: .init(.i, modifiers: [.control, .option, .command]))
    static let startCapture = Self("startCapture", default: .init(.a, modifiers: [.option]))
}
