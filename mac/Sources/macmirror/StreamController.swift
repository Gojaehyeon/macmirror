import Foundation
import CoreGraphics

/// Owns the whole streaming engine (virtual display + single-port server +
/// capture) and exposes simple start/stop so the menu bar can drive it.
/// All callbacks are delivered on the main queue.
final class StreamController {

    struct Config {
        var width: UInt32 = 1600
        var height: UInt32 = 1000
        var fps: Int = 30
        var quality: Double = 0.6
        var port: UInt16 = 8888
        var refresh: Double = 60
        var hidpi: Bool = false
        var name: String = "Tesla Display"
        var useMainDisplay: Bool = false
        /// Global desktop coordinates for the virtual display origin. Defaults
        /// push it far right so it doesn't overlap real displays.
        var originX: Int32 = 10000
        var originY: Int32 = 0
    }

    private(set) var isRunning = false
    var config: Config

    var onStateChange: ((Bool) -> Void)?
    var onClientCount: ((Int) -> Void)?
    var onError: ((String) -> Void)?

    private var virtualDisplay: VirtualDisplayManager?
    private var server: Server?
    private var capturer: ScreenCapturer?

    init(config: Config) {
        self.config = config
    }

    /// Local http://<ip>:<port> for every LAN interface (for same-network browsers).
    var localURLs: [String] {
        lanIPv4Addresses().map { "http://\($0):\(config.port)" }
    }

    func start() {
        guard !isRunning else { return }

        let targetDisplayID: CGDirectDisplayID
        if config.useMainDisplay {
            targetDisplayID = CGMainDisplayID()
        } else {
            guard let vd = VirtualDisplayManager(width: config.width,
                                                 height: config.height,
                                                 refreshRate: config.refresh,
                                                 hiDPI: config.hidpi,
                                                 name: config.name) else {
                report("가상 디스플레이를 만들지 못했습니다. (이 macOS 버전에서 비공개 API가 막혔을 수 있습니다)")
                return
            }
            virtualDisplay = vd
            targetDisplayID = vd.displayID
            // Position the virtual display in an unused part of the desktop so
            // windows can actually be dragged onto it.
            vd.setOrigin(x: config.originX, y: config.originY)
        }

        do {
            let server = try Server(port: config.port, html: Data(viewerHTML.utf8))
            server.onClientCountChange = { [weak self] count in
                DispatchQueue.main.async { self?.onClientCount?(count) }
            }
            server.onFatalError = { [weak self] msg in
                DispatchQueue.main.async { self?.report(msg); self?.stop() }
            }
            server.start()
            self.server = server
        } catch {
            report("서버를 시작하지 못했습니다: \(error.localizedDescription)")
            cleanup()
            return
        }

        let cap = ScreenCapturer(quality: config.quality)
        cap.onJPEG = { [weak self] data in self?.server?.broadcast(data) }
        self.capturer = cap

        isRunning = true
        onStateChange?(true)

        let displayID = targetDisplayID
        let fps = config.fps
        Task { [weak self] in
            do {
                try await cap.start(displayID: displayID, fps: fps)
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.report("""
                    화면 캡처를 시작하지 못했습니다.
                    시스템 설정 → 개인정보 보호 및 보안 → 화면 기록 에서 mactesla 를 켠 뒤 다시 시도하세요.
                    """)
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isRunning || virtualDisplay != nil || server != nil else { return }
        cleanup()
        isRunning = false
        onStateChange?(false)
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.start()
        }
    }

    private func cleanup() {
        let cap = capturer
        Task { await cap?.stop() }
        server?.cancel()
        capturer = nil
        server = nil
        virtualDisplay = nil   // deinit tears the virtual display down
    }

    private func report(_ message: String) {
        onError?(message)
    }
}

/// IPv4 addresses of the Wi-Fi/Ethernet interfaces (for building local URLs).
func lanIPv4Addresses() -> [String] {
    var addresses: [String] = []
    var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
    defer { freeifaddrs(ifaddrPtr) }

    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let cur = ptr {
        defer { ptr = cur.pointee.ifa_next }
        let flags = Int32(cur.pointee.ifa_flags)
        guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
        guard let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
        let name = String(cString: cur.pointee.ifa_name)
        guard name.hasPrefix("en") else { continue }

        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                                 &host, socklen_t(host.count),
                                 nil, 0, NI_NUMERICHOST)
        if result == 0 {
            let ip = String(cString: host)
            if !ip.isEmpty, !addresses.contains(ip) { addresses.append(ip) }
        }
    }
    return addresses
}
