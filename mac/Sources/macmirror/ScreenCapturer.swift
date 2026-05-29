import Foundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo
import ImageIO

/// Captures a single display via ScreenCaptureKit and emits JPEG frames.
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let ciContext: CIContext
    private let jpegQuality: Double
    private let sampleQueue = DispatchQueue(label: "com.mactesla.capture.samples")
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Called on the sample queue with an encoded JPEG for each captured frame.
    var onJPEG: ((Data) -> Void)?

    init(quality: Double) {
        self.jpegQuality = quality
        // GPU-backed context; we disable intermediate caching since every frame is unique.
        self.ciContext = CIContext(options: [.cacheIntermediates: false])
        super.init()
    }

    /// Locate the SCDisplay for `displayID`, retrying briefly because a freshly
    /// created virtual display can take a moment to appear in shareable content.
    private func resolveDisplay(_ displayID: CGDirectDisplayID) async throws -> SCDisplay {
        for attempt in 0..<20 {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            if let match = content.displays.first(where: { $0.displayID == displayID }) {
                return match
            }
            if attempt == 0 {
                FileHandle.standardError.write(Data("⏳ 디스플레이(ID \(displayID))가 나타나길 기다리는 중…\n".utf8))
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw CaptureError.displayNotFound(displayID)
    }

    func start(displayID: CGDirectDisplayID, fps: Int) async throws {
        let display = try await resolveDisplay(displayID)

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = display.width      // points == pixels for a non-HiDPI display
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = true
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream

        FileHandle.standardError.write(
            Data("🎥 캡처 시작: \(display.width)×\(display.height) @ \(fps)fps\n".utf8))
    }

    func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Only forward frames the system marked as complete (skip idle/blank/duplicate).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let info = attachments.first,
           let statusRaw = info[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): jpegQuality
        ]
        guard let data = ciContext.jpegRepresentation(of: image,
                                                       colorSpace: colorSpace,
                                                       options: options) else { return }
        onJPEG?(data)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write(Data("⚠️  캡처 중단됨: \(error.localizedDescription)\n".utf8))
    }

    enum CaptureError: LocalizedError {
        case displayNotFound(CGDirectDisplayID)
        var errorDescription: String? {
            switch self {
            case .displayNotFound(let id):
                return "디스플레이 ID \(id)를 찾을 수 없습니다 (화면 기록 권한 또는 가상 디스플레이 생성 실패)."
            }
        }
    }
}
