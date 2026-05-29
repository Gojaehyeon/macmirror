import Foundation

/// Runs a Cloudflare "quick tunnel" (`cloudflared tunnel --url ...`) so the
/// local stream gets a public https URL the Tesla browser will accept.
/// (The Tesla browser blocks private LAN IPs, so a public hostname is required.)
final class Tunnel {
    private var process: Process?
    private(set) var publicURL: String?
    private(set) var shortURL: String?

    /// Called on the main queue when the (long) public URL becomes available.
    var onURL: ((String) -> Void)?
    /// Called on the main queue when the short, easy-to-type URL is ready.
    var onShortURL: ((String) -> Void)?
    /// Called on the main queue with status / error text.
    var onStatus: ((String) -> Void)?

    private static let candidatePaths = [
        "/opt/homebrew/bin/cloudflared",
        "/usr/local/bin/cloudflared",
        "/usr/bin/cloudflared"
    ]

    private var binaryPath: String? {
        Self.candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isInstalled: Bool { binaryPath != nil }

    func start(localPort: UInt16) {
        guard process == nil else { return }
        guard let binary = binaryPath else {
            DispatchQueue.main.async {
                self.onStatus?("cloudflared 미설치 — 터미널에서 `brew install cloudflared` 후 다시 실행하세요.")
            }
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["tunnel", "--url", "http://localhost:\(localPort)", "--no-autoupdate"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            guard let self, self.publicURL == nil else { return }
            if let range = text.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#,
                                      options: .regularExpression) {
                let url = String(text[range])
                self.publicURL = url
                FileHandle.standardError.write(Data("🌐 공개 주소: \(url)\n".utf8))
                DispatchQueue.main.async { self.onURL?(url) }
                self.shorten(url)
            }
        }
        proc.terminationHandler = { [weak self] _ in
            self?.publicURL = nil
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            DispatchQueue.main.async {
                self.onStatus?("cloudflared 실행 실패: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        publicURL = nil
        shortURL = nil
    }

    /// Turn the long trycloudflare URL into a short link that's far easier to
    /// type on the Tesla touchscreen. Free, no account/token. Best-effort, with
    /// a fallback (is.gd / tinyurl reject trycloudflare URLs, so we use these).
    private func shorten(_ longURL: String) {
        shortenViaSpoo(longURL) { [weak self] short in
            if let short {
                self?.setShort(short.replacingOccurrences(of: "http://", with: "https://"))
            } else {
                self?.shortenViaCleanuri(longURL) { short in
                    if let short { self?.setShort(short) }
                }
            }
        }
    }

    private func setShort(_ url: String) {
        shortURL = url
        FileHandle.standardError.write(Data("🔗 짧은 주소: \(url)\n".utf8))
        DispatchQueue.main.async { self.onShortURL?(url) }
    }

    private func postForm(_ endpoint: String, longURL: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: endpoint) else { completion(nil); return }
        let encoded = longURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? longURL
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = Data("url=\(encoded)".utf8)
        URLSession.shared.dataTask(with: req) { data, _, _ in completion(data) }.resume()
    }

    private func json(_ data: Data?, _ key: String) -> String? {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = obj[key] as? String else { return nil }
        return value
    }

    private func shortenViaSpoo(_ longURL: String, completion: @escaping (String?) -> Void) {
        postForm("https://spoo.me/", longURL: longURL) { [weak self] data in
            completion(self?.json(data, "short_url"))
        }
    }

    private func shortenViaCleanuri(_ longURL: String, completion: @escaping (String?) -> Void) {
        postForm("https://cleanuri.com/api/v1/shorten", longURL: longURL) { [weak self] data in
            completion(self?.json(data, "result_url"))
        }
    }
}
