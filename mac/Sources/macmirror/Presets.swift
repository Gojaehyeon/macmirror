import Foundation

/// Named virtual-display sizes. Sizes are picked so macOS 26.5 keeps the display
/// visible in System Settings (tiny ones get hidden) while preserving the
/// target device's screen aspect ratio.
struct DevicePreset: Equatable {
    let name: String
    let category: String
    let width: UInt32
    let height: UInt32

    static let all: [DevicePreset] = [
        // iPhone — defaults to Pro Max sized
        DevicePreset(name: "iPhone Pro Max",  category: "iPhone", width:  860, height: 1864),
        DevicePreset(name: "iPhone Pro",      category: "iPhone", width:  786, height: 1704),
        DevicePreset(name: "iPhone Mini",     category: "iPhone", width:  720, height: 1560),

        // iPad
        DevicePreset(name: "iPad Pro 13\"",   category: "iPad",   width: 1664, height: 2160),
        DevicePreset(name: "iPad Pro 11\"",   category: "iPad",   width: 1668, height: 2388),
        DevicePreset(name: "iPad Air",        category: "iPad",   width: 1640, height: 2360),
        DevicePreset(name: "iPad mini",       category: "iPad",   width: 1488, height: 2266),

        // Generic shapes
        DevicePreset(name: "Square 1:1",      category: "기타",    width: 1200, height: 1200),
        DevicePreset(name: "Landscape 16:9",  category: "기타",    width: 1920, height: 1080)
    ]

    static let `default`: DevicePreset = all.first!  // iPhone Pro Max
}
