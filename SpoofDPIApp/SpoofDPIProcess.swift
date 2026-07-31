import Darwin
import Foundation

enum SpoofDPIProcessError: LocalizedError {
    case binaryMissing
    case binaryNotExecutable
    case alreadyRunning
    case portTimeout
    case spawnFailed(String)
    case exitedEarly(Int32, String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "SpoofDPI binary not found in the app bundle."
        case .binaryNotExecutable:
            return "SpoofDPI binary is not executable."
        case .alreadyRunning:
            return "SpoofDPI is already running."
        case .portTimeout:
            return "Timed out waiting for SpoofDPI on 127.0.0.1:8080."
        case .spawnFailed(let message):
            return "Failed to start SpoofDPI: \(message)"
        case .exitedEarly(let code, let output):
            let detail = output.isEmpty ? "exit code \(code)" : output
            return "SpoofDPI exited early (\(detail))."
        }
    }
}

@MainActor
final class SpoofDPIProcess {
    static let address = "127.0.0.1"
    static let port: UInt16 = 8080

    private var process: Process?
    private var stderrPipe: Pipe?
    private var stderrBuffer = ""

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start() async throws {
        if process?.isRunning == true {
            throw SpoofDPIProcessError.alreadyRunning
        }

        let binaryURL = try Self.resolveBinaryURL()
        try Self.ensureExecutable(at: binaryURL)

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [
            "-silent",
            "-addr", Self.address,
            "-port", String(Self.port),
            "-dns-ipv4-only",
            "-system-proxy=false"
        ]

        let stderr = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        stderrBuffer = ""

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.stderrBuffer.append(chunk)
            }
        }

        process.terminationHandler = { _ in
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
        } catch {
            throw SpoofDPIProcessError.spawnFailed(error.localizedDescription)
        }

        self.process = process
        self.stderrPipe = stderr

        let ready = await Self.waitForPort(host: Self.address, port: Self.port, timeout: 8)
        if !ready {
            let output = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = process.terminationStatus
            let exited = !process.isRunning
            stop()
            if exited {
                throw SpoofDPIProcessError.exitedEarly(status, output)
            }
            throw SpoofDPIProcessError.portTimeout
        }

        if !process.isRunning {
            let output = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = process.terminationStatus
            stop()
            throw SpoofDPIProcessError.exitedEarly(status, output)
        }
    }

    func stop() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if let running = process, running.isRunning {
            running.terminate()
            let deadline = Date().addingTimeInterval(2)
            while running.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if running.isRunning {
                kill(running.processIdentifier, SIGKILL)
            }
        }
        process = nil
        stderrPipe = nil
        stderrBuffer = ""
    }

    private static func resolveBinaryURL() throws -> URL {
        if let bundled = Bundle.main.url(forResource: "spoofdpi", withExtension: nil) {
            return bundled
        }
        throw SpoofDPIProcessError.binaryMissing
    }

    private static func ensureExecutable(at url: URL) throws {
        var values = try url.resourceValues(forKeys: [.isExecutableKey])
        if values.isExecutable == true { return }

        guard chmod(url.path, 0o755) == 0 else {
            throw SpoofDPIProcessError.binaryNotExecutable
        }
        values = try url.resourceValues(forKeys: [.isExecutableKey])
        guard values.isExecutable == true else {
            throw SpoofDPIProcessError.binaryNotExecutable
        }
    }

    private static func waitForPort(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isPortOpen(host: host, port: port) {
                return true
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return isPortOpen(host: host, port: port)
    }

    private static func isPortOpen(host: String, port: UInt16) -> Bool {
        var hints = addrinfo(
            ai_flags: AI_NUMERICHOST,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let info else {
            return false
        }
        defer { freeaddrinfo(info) }

        let sock = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        _ = setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        return connect(sock, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0
    }
}
