// StitchResultTests.swift
// PicelfIOSTests — Unit tests for StitchResult model

import XCTest
@testable import Picelf

final class StitchResultTests: XCTestCase {

    // MARK: - Codable roundtrip

    func test_codable_roundtrip() throws {
        let original = StitchResult(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1700000000),
            width: 1080,
            height: 5400,
            fileName: "test-image.png",
            thumbnailFileName: "test-image-thumb.png"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StitchResult.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.width, original.width)
        XCTAssertEqual(decoded.height, original.height)
        XCTAssertEqual(decoded.fileName, original.fileName)
        XCTAssertEqual(decoded.thumbnailFileName, original.thumbnailFileName)
        // Date comparison with tolerance for ISO 8601 second-level precision
        XCTAssertEqual(decoded.date.timeIntervalSince1970,
                       original.date.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    func test_codable_arrayRoundtrip() throws {
        let results = [
            StitchResult(width: 1080, height: 2000, fileName: "a.png", thumbnailFileName: "a-thumb.png"),
            StitchResult(width: 800, height: 3000, fileName: "b.png", thumbnailFileName: "b-thumb.png"),
        ]

        let encoder = JSONEncoder()
        let data = try encoder.encode(results)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([StitchResult].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].fileName, "a.png")
        XCTAssertEqual(decoded[1].fileName, "b.png")
    }

    // MARK: - Equatable

    func test_equatable_sameValues_areEqual() {
        let id = UUID()
        let date = Date()
        let a = StitchResult(id: id, date: date, width: 100, height: 200, fileName: "f.png", thumbnailFileName: "f-thumb.png")
        let b = StitchResult(id: id, date: date, width: 100, height: 200, fileName: "f.png", thumbnailFileName: "f-thumb.png")
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentID_areNotEqual() {
        let date = Date()
        let a = StitchResult(id: UUID(), date: date, width: 100, height: 200, fileName: "f.png", thumbnailFileName: "f-thumb.png")
        let b = StitchResult(id: UUID(), date: date, width: 100, height: 200, fileName: "f.png", thumbnailFileName: "f-thumb.png")
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentDimensions_areNotEqual() {
        let id = UUID()
        let date = Date()
        let a = StitchResult(id: id, date: date, width: 100, height: 200, fileName: "f.png", thumbnailFileName: "f-thumb.png")
        let b = StitchResult(id: id, date: date, width: 100, height: 300, fileName: "f.png", thumbnailFileName: "f-thumb.png")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Identifiable

    func test_identifiable_idIsUUID() {
        let result = StitchResult(width: 100, height: 200, fileName: "x.png", thumbnailFileName: "x-thumb.png")
        // id should be a valid UUID
        XCTAssertNotNil(UUID(uuidString: result.id.uuidString))
    }
}
