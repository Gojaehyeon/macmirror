import Foundation
import CoreGraphics
import CVirtualDisplay

/// Swift lifetime wrapper around the private CGVirtualDisplay bridge.
/// The virtual display exists for as long as this object is alive.
final class VirtualDisplayManager {
    private let handle: VDHandle
    let displayID: CGDirectDisplayID

    init?(width: UInt32, height: UInt32, refreshRate: Double, hiDPI: Bool, name: String) {
        var displayID: UInt32 = 0
        let handle: VDHandle? = name.withCString { cName in
            VDCreate(width, height, refreshRate, hiDPI ? 1 : 0, cName, &displayID)
        }
        guard let handle, displayID != 0 else { return nil }
        self.handle = handle
        self.displayID = displayID
    }

    deinit {
        VDRelease(handle)
    }

    /// Place the virtual display at an explicit position in the global desktop
    /// space. macOS 26.5 + private CGVirtualDisplay creates the display at (0,0)
    /// overlapping the main display, which hides it from arrangement UI and
    /// prevents window placement. Pushing it to an empty region (far right) lets
    /// windows be dragged to it.
    func setOrigin(x: Int32, y: Int32) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
        CGConfigureDisplayOrigin(config, displayID, x, y)
        _ = CGCompleteDisplayConfiguration(config, .forSession)
    }
}
