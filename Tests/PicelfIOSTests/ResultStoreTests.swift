// ResultStoreTests.swift
// PicelfIOSTests — Unit tests for ResultStore

import XCTest
@testable import Picelf

@MainActor
final class ResultStoreTests: XCTestCase {

    private var store: ResultStore!

    override func setUp() {
        super.setUp()
        store = ResultStore()
        // Clean up any leftover results from previous test runs
        for result in store.results {
            store.delete(result)
        }
    }

    override func tearDown() {
        // Clean up all results created during tests
        if let store = store {
            for result in store.results {
                store.delete(result)
            }
        }
        store = nil
        super.tearDown()
    }

    // MARK: - Save

    func test_save_createsResultWithCorrectDimensions() {
        let image = TestHelpers.makeSolidColorUIImage(width: 200, height: 400)!
        let result = store.save(image: image)

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.width, 200)
        XCTAssertEqual(result!.height, 400)
    }

    func test_save_addsToResultsList() {
        let image = TestHelpers.makeSolidColorUIImage(width: 100, height: 200)!
        let result = store.save(image: image)

        XCTAssertNotNil(result)
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.id, result!.id)
    }

    func test_save_multipleSaves_insertsAtFront() {
        let image1 = TestHelpers.makeSolidColorUIImage(width: 100, height: 200)!
        let image2 = TestHelpers.makeSolidColorUIImage(width: 300, height: 400)!

        let result1 = store.save(image: image1)!
        let result2 = store.save(image: image2)!

        XCTAssertEqual(store.results.count, 2)
        // Most recent should be first
        XCTAssertEqual(store.results.first?.id, result2.id)
        XCTAssertEqual(store.results.last?.id, result1.id)
    }

    // MARK: - Load Thumbnail

    func test_loadThumbnail_afterSave_returnsNonNil() {
        let image = TestHelpers.makeSolidColorUIImage(width: 400, height: 800)!
        let result = store.save(image: image)!

        let thumbnail = store.loadThumbnail(for: result)
        XCTAssertNotNil(thumbnail, "Thumbnail should be loadable after save")
    }

    func test_loadThumbnail_forDeletedResult_returnsNil() {
        let image = TestHelpers.makeSolidColorUIImage(width: 400, height: 800)!
        let result = store.save(image: image)!
        store.delete(result)

        let thumbnail = store.loadThumbnail(for: result)
        XCTAssertNil(thumbnail, "Thumbnail should be nil after deletion")
    }

    // MARK: - Load Full Image

    func test_loadFullImage_afterSave_returnsNonNil() {
        let image = TestHelpers.makeSolidColorUIImage(width: 300, height: 600)!
        let result = store.save(image: image)!

        let loaded = store.loadFullImage(for: result)
        XCTAssertNotNil(loaded, "Full image should be loadable after save")
    }

    func test_loadFullImage_correctDimensions() {
        let image = TestHelpers.makeSolidColorUIImage(width: 300, height: 600)!
        let result = store.save(image: image)!

        let loaded = store.loadFullImage(for: result)
        XCTAssertNotNil(loaded)
        // UIImage loaded from PNG at scale 1.0
        XCTAssertEqual(Int(loaded!.size.width), 300)
        XCTAssertEqual(Int(loaded!.size.height), 600)
    }

    // MARK: - Delete

    func test_delete_removesFromList() {
        let image = TestHelpers.makeSolidColorUIImage(width: 100, height: 200)!
        let result = store.save(image: image)!
        XCTAssertEqual(store.results.count, 1)

        store.delete(result)
        XCTAssertEqual(store.results.count, 0)
    }

    func test_delete_removesFiles() {
        let image = TestHelpers.makeSolidColorUIImage(width: 100, height: 200)!
        let result = store.save(image: image)!

        // Verify files exist before deletion
        let fullImage = store.loadFullImage(for: result)
        XCTAssertNotNil(fullImage)

        store.delete(result)

        // Files should be gone
        let afterDelete = store.loadFullImage(for: result)
        XCTAssertNil(afterDelete)
    }

    func test_deleteBatch_removesMultiple() {
        let img1 = TestHelpers.makeSolidColorUIImage(width: 100, height: 200)!
        let img2 = TestHelpers.makeSolidColorUIImage(width: 100, height: 200)!
        let img3 = TestHelpers.makeSolidColorUIImage(width: 100, height: 200)!

        let r1 = store.save(image: img1)!
        let r2 = store.save(image: img2)!
        let _ = store.save(image: img3)!

        store.delete(Set([r1.id, r2.id]))
        XCTAssertEqual(store.results.count, 1)
    }

    // MARK: - Persistence

    func test_persistence_savedResults_surviveReInit() {
        let image = TestHelpers.makeSolidColorUIImage(width: 150, height: 300)!
        let result = store.save(image: image)!

        // Create a new store instance — should load from persisted JSON
        let newStore = ResultStore()
        XCTAssertFalse(newStore.results.isEmpty, "New store should load persisted results")
        XCTAssertTrue(newStore.results.contains(where: { $0.id == result.id }),
                      "Persisted results should include the saved result")

        // Clean up
        newStore.delete(result)
    }
}
