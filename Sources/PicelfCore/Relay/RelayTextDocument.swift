import Foundation

struct RelayTextBox: Codable, Equatable, Identifiable {
    enum Alignment: String, Codable, CaseIterable { case left, center, right }
    enum Color: String, Codable, CaseIterable { case charcoal, white, emerald, red, blue }
    var id = UUID()
    var text = ""
    var x: Double
    var y: Double
    var width: Double
    var fontSize: Double
    var bold = false
    var color: Color = .charcoal
    var alignment: Alignment = .left
    var background = false
}

struct RelayTextDocument: Codable, Equatable {
    var version = 1
    var boxes: [RelayTextBox] = []
    static let filename = "pad-text.json"
    func encoded() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 2 * 1024 * 1024 else { throw RelayError.message(L10n.localized("文字标注内容过大。", "Text annotations are too large.")) }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 2 * 1024 * 1024 else { throw RelayError.message(L10n.localized("文字标注内容过大。", "Text annotations are too large.")) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    private func validate() throws {
        guard version == 1, boxes.count <= 200, Set(boxes.map(\.id)).count == boxes.count,
              boxes.allSatisfy({ box in
                  [box.x, box.y, box.width, box.fontSize].allSatisfy(\.isFinite)
                  && box.x >= 0 && box.y >= 0 && box.x <= 16_384 && box.y <= 16_384
                  && box.width >= 1 && box.width <= 16_384 && box.fontSize >= 8 && box.fontSize <= 512
                  && box.text.utf8.count <= 16_384
              }) else { throw RelayError.message(L10n.localized("文字标注格式不正确，请更新两端 Picelf。", "The text annotation format is invalid. Update Picelf on both devices.")) }
    }
}
