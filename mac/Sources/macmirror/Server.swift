import Foundation
import Network
import CryptoKit

/// Single-port server: serves the viewer page over HTTP **and** streams JPEG
/// frames over WebSocket on the *same* port. One port means one public hostname,
/// which is what a Cloudflare/ngrok tunnel exposes (the Tesla browser blocks
/// private LAN IPs, so the stream must go out through a public tunnel).
///
/// HTTP and the WebSocket handshake/framing are implemented by hand so both can
/// share the listener.
final class Server {
    private final class Client {
        let connection: NWConnection
        var inflight = false
        init(_ connection: NWConnection) { self.connection = connection }
    }

    private let port: NWEndpoint.Port
    private let portNumber: UInt16
    private let listener: NWListener
    private let html: Data
    private let queue = DispatchQueue(label: "com.mactesla.server")
    private var clients: [ObjectIdentifier: Client] = [:]
    private var lastFrame: Data?

    private(set) var clientCount = 0
    var onClientCountChange: ((Int) -> Void)?
    var onFatalError: ((String) -> Void)?

    init(port: UInt16, html: Data) throws {
        self.portNumber = port
        self.port = NWEndpoint.Port(rawValue: port)!
        self.html = html
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        self.listener = try NWListener(using: params, on: self.port)
    }

    func start() {
        let portNumber = self.portNumber
        listener.stateUpdateHandler = { [weak self] state in
            FileHandle.standardError.write(Data("📡 listener[\(portNumber)] → \(state)\n".utf8))
            if case .failed(let error) = state {
                let msg = "포트 \(portNumber) 를 열 수 없습니다 (\(error)). 다른 포트를 쓰세요."
                FileHandle.standardError.write(Data("❌ \(msg)\n".utf8))
                self?.onFatalError?(msg)
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
    }

    func cancel() {
        listener.stateUpdateHandler = nil
        listener.cancel()
        queue.async {
            for (_, client) in self.clients { client.connection.cancel() }
            self.clients.removeAll()
            self.clientCount = 0
            self.lastFrame = nil
        }
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.removeClient(id) }
            default:
                break
            }
        }
        conn.start(queue: queue)
        readRequest(conn, buffer: Data())
    }

    private func removeClient(_ id: ObjectIdentifier) {
        if clients.removeValue(forKey: id) != nil {
            clientCount = clients.count
            onClientCountChange?(clientCount)
        }
    }

    /// Accumulate bytes until the end of the HTTP header block, then route.
    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            if error != nil { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf.subdata(in: buf.startIndex..<headerEnd.lowerBound)
                self.route(conn, header: String(decoding: headerData, as: UTF8.self))
            } else if isComplete || buf.count > 1_000_000 {
                conn.cancel()
            } else {
                self.readRequest(conn, buffer: buf)
            }
        }
    }

    private func route(_ conn: NWConnection, header: String) {
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { conn.cancel(); return }
        let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // WebSocket upgrade?
        if headers["upgrade"]?.lowercased().contains("websocket") == true,
           let key = headers["sec-websocket-key"] {
            upgradeToWebSocket(conn, key: key)
            return
        }

        // Plain HTTP.
        let body: Data, status: String, contentType: String
        switch path {
        case "/", "/index.html", "/viewer":
            body = html; status = "200 OK"; contentType = "text/html; charset=utf-8"
        case "/health":
            body = Data("ok".utf8); status = "200 OK"; contentType = "text/plain"
        case "/frame":
            // Latest JPEG snapshot — used by clients that can't speak WebSocket
            // (e.g. URLSessionWebSocketTask is blocked on some watchOS builds).
            // route() already runs on `queue`, so this read is safe.
            if let frame = self.lastFrame {
                body = frame; status = "200 OK"; contentType = "image/jpeg"
            } else {
                body = Data("no frame yet".utf8); status = "503 Service Unavailable"; contentType = "text/plain"
            }
        default:
            body = Data("not found".utf8); status = "404 Not Found"; contentType = "text/plain"
        }
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - WebSocket

    private func upgradeToWebSocket(_ conn: NWConnection, key: String) {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let accept = Data(Insecure.SHA1.hash(data: Data((key + magic).utf8))).base64EncodedString()
        let response = "HTTP/1.1 101 Switching Protocols\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Accept: \(accept)\r\n\r\n"
        conn.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { conn.cancel(); return }
            let id = ObjectIdentifier(conn)
            let client = Client(conn)
            self.clients[id] = client
            self.clientCount = self.clients.count
            self.onClientCountChange?(self.clientCount)
            if let frame = self.lastFrame { self.sendFrame(frame, to: client) }
            self.drain(conn) // consume client frames; cancel on close
        })
    }

    /// Keep receiving so closes are noticed; inbound frames are discarded.
    private func drain(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] _, _, isComplete, error in
            if error != nil || isComplete { conn.cancel(); return }
            self?.drain(conn)
        }
    }

    /// Broadcast a JPEG frame to all viewers, dropping frames for any client
    /// that hasn't finished its previous send (keeps slow clients low-latency).
    func broadcast(_ jpeg: Data) {
        queue.async {
            self.lastFrame = jpeg
            for (_, client) in self.clients where !client.inflight {
                self.sendFrame(jpeg, to: client)
            }
        }
    }

    private func sendFrame(_ jpeg: Data, to client: Client) {
        client.inflight = true
        client.connection.send(content: Self.encodeBinaryFrame(jpeg),
                               completion: .contentProcessed { [weak client] _ in
            client?.inflight = false
        })
    }

    /// RFC 6455 server→client binary frame (FIN + opcode 0x2, unmasked).
    static func encodeBinaryFrame(_ payload: Data) -> Data {
        var frame = Data([0x82])
        let len = payload.count
        if len <= 125 {
            frame.append(UInt8(len))
        } else if len <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127)
            var be = UInt64(len).bigEndian
            withUnsafeBytes(of: &be) { frame.append(contentsOf: $0) }
        }
        frame.append(payload)
        return frame
    }
}
