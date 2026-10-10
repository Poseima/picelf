// RegionPreset.swift
// Picelf — Region Preset Model
//
// A named, user-defined capture region size (e.g. "Full HD 1920x1080").
// Presets are persisted as part of AppPreferences.
//
// Target: macOS 14+, Swift 5.9+

import Foundation

struct RegionPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var width: Int
    var height: Int

    init(name: String, width: Int, height: Int) {
        self.id = UUID()
        self.name = name
        self.width = width
        self.height = height
    }
}
