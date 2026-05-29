import AppKit

// Optional CLI overrides (a double-clicked .app just uses the defaults).
func parseConfig(_ args: [String]) -> StreamController.Config {
    var c = StreamController.Config()
    // iPhone Pro Max aspect ≈ 0.461 (430×932 pt). Use a 2× virtual display so
    // macOS keeps it visible in System Settings → Displays.
    let p = DevicePreset.default
    c.width = p.width
    c.height = p.height
    c.fps = 30
    c.quality = 0.65
    c.port = 8890
    c.name = "macmirror"
    c.originX = 12000
    c.originY = 0

    var i = 1
    func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
    while i < args.count {
        switch args[i] {
        case "--width":   if let v = next(), let n = UInt32(v) { c.width = n }
        case "--height":  if let v = next(), let n = UInt32(v) { c.height = n }
        case "--fps":     if let v = next(), let n = Int(v) { c.fps = n }
        case "--quality": if let v = next(), let n = Double(v) { c.quality = n }
        case "--port":    if let v = next(), let n = UInt16(v) { c.port = n }
        case "--refresh": if let v = next(), let n = Double(v) { c.refresh = n }
        case "--name":    if let v = next() { c.name = v }
        case "--hidpi":   c.hidpi = true
        case "--source":  if let v = next() { c.useMainDisplay = (v == "main") }
        case "--preset":
            if let v = next(), let preset = DevicePreset.all.first(where: { $0.name.caseInsensitiveCompare(v) == .orderedSame }) {
                c.width = preset.width
                c.height = preset.height
            }
        default: break
        }
        i += 1
    }
    return c
}

let controller = StreamController(config: parseConfig(CommandLine.arguments))

let app = NSApplication.shared
let delegate = AppDelegate(controller: controller)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
