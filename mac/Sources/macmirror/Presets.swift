import Foundation

/// Named virtual-display sizes. Dimensions are **portrait, in points (1×)** and
/// account for Safari's actual usable viewport (i.e. the visible canvas after
/// the URL bar, Dynamic Island, and home indicator).
///
/// The actual virtual-display pixel size is `width × scale`. macOS 26.5 also
/// hides too-small virtual displays from System Settings UI, so 2× is a sane
/// minimum.
struct DevicePreset: Equatable {
    let name: String
    let category: String
    /// Portrait width in points (1×).
    let width: UInt32
    /// Portrait height in points (1×).
    let height: UInt32

    static let all: [DevicePreset] = [
        // iPhone (Safari usable viewport, 1× pt)
        DevicePreset(name: "iPhone Pro Max",  category: "iPhone", width: 430, height: 778),
        DevicePreset(name: "iPhone Pro",      category: "iPhone", width: 393, height: 717),
        DevicePreset(name: "iPhone Mini",     category: "iPhone", width: 360, height: 645),

        // iPad (Safari usable viewport, 1× pt)
        DevicePreset(name: "iPad Pro 13\"",   category: "iPad",   width: 1032, height: 1294),
        DevicePreset(name: "iPad Pro 11\"",   category: "iPad",   width:  834, height: 1135),
        DevicePreset(name: "iPad Air",        category: "iPad",   width:  820, height: 1135),
        DevicePreset(name: "iPad mini",       category: "iPad",   width:  744, height: 1071),

        // Generic shapes (orientation-neutral)
        DevicePreset(name: "Square 1:1",      category: "기타",    width:  600, height:  600),
        DevicePreset(name: "16:9",            category: "기타",    width:  540, height:  960)
    ]

    static let `default`: DevicePreset = all.first!  // iPhone Pro Max

    /// Returns (width, height) at the given scale, swapped if `landscape`.
    func dimensions(scale: UInt32, landscape: Bool) -> (UInt32, UInt32) {
        let w = width * scale
        let h = height * scale
        return landscape ? (h, w) : (w, h)
    }
}

enum Orientation: String {
    case portrait = "세로"
    case landscape = "가로"
}

enum DisplayScale: UInt32, CaseIterable {
    case x2 = 2
    case x3 = 3
    case x4 = 4

    var label: String {
        switch self {
        case .x2: return "2× (선명)"
        case .x3: return "3× (Retina)"
        case .x4: return "4× (초고해상도)"
        }
    }
}
