import Foundation

/// Named virtual-display sizes. Dimensions are **portrait, in pixels**, and
/// account for Safari's actual usable viewport (i.e. the visible canvas after
/// the URL bar, Dynamic Island, and home indicator).
///
/// Pixel sizes are kept at roughly 2× pt to (a) stay visible in macOS 26.5
/// System Settings UI (tiny virtual displays get hidden) and (b) give clients
/// crisp content out of the box. HiDPI mode can be toggled separately.
struct DevicePreset: Equatable {
    let name: String
    let category: String
    /// Portrait pixel width.
    let width: UInt32
    /// Portrait pixel height.
    let height: UInt32

    static let all: [DevicePreset] = [
        // iPhone (Safari usable viewport)
        DevicePreset(name: "iPhone Pro Max",  category: "iPhone", width:  860, height: 1556),
        DevicePreset(name: "iPhone Pro",      category: "iPhone", width:  786, height: 1434),
        DevicePreset(name: "iPhone Mini",     category: "iPhone", width:  720, height: 1290),

        // iPad (Safari usable viewport)
        DevicePreset(name: "iPad Pro 13\"",   category: "iPad",   width: 2064, height: 2588),
        DevicePreset(name: "iPad Pro 11\"",   category: "iPad",   width: 1668, height: 2270),
        DevicePreset(name: "iPad Air",        category: "iPad",   width: 1640, height: 2270),
        DevicePreset(name: "iPad mini",       category: "iPad",   width: 1488, height: 2142),

        // Generic shapes (orientation-neutral)
        DevicePreset(name: "Square 1:1",      category: "기타",    width: 1200, height: 1200),
        DevicePreset(name: "16:9",            category: "기타",    width: 1080, height: 1920)
    ]

    static let `default`: DevicePreset = all.first!  // iPhone Pro Max

    /// Returns (width, height) swapped if `landscape`.
    func dimensions(landscape: Bool) -> (UInt32, UInt32) {
        landscape ? (height, width) : (width, height)
    }
}

enum Orientation: String {
    case portrait = "세로"
    case landscape = "가로"
}
