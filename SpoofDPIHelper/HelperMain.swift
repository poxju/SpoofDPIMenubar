import Foundation

enum QuicBlockEngine {
    static let anchorName = "com.spoofdpi.quic"
    static let anchorPath = "/etc/pf.anchors/com.spoofdpi.menubar"
    static let pfConfPath = "/etc/pf.conf"
    static let marker = "# com.spoofdpi.quic"

    static func install() throws {
        try FileManager.default.createDirectory(
            atPath: "/etc/pf.anchors",
            withIntermediateDirectories: true
        )
        let rule = "block drop quick proto udp from any to any port 443\n"
        try rule.write(toFile: anchorPath, atomically: true, encoding: .utf8)

        var conf = (try? String(contentsOfFile: pfConfPath, encoding: .utf8)) ?? ""
        if !conf.contains(marker) {
            conf += """

            \(marker)
            anchor "\(anchorName)"
            load anchor "\(anchorName)" from "\(anchorPath)"
            """
            try conf.write(toFile: pfConfPath, atomically: true, encoding: .utf8)
        }

        _ = try run("/sbin/pfctl", ["-f", pfConfPath])
        _ = try? run("/sbin/pfctl", ["-e"])
    }

    static func remove() throws {
        try? FileManager.default.removeItem(atPath: anchorPath)

        guard var conf = try? String(contentsOfFile: pfConfPath, encoding: .utf8),
              conf.contains(marker)
        else {
            _ = try? run("/sbin/pfctl", ["-f", pfConfPath])
            return
        }

        let raw = conf.components(separatedBy: "\n")
        var filtered: [String] = []
        var i = 0
        while i < raw.count {
            let line = raw[i]
            if line.contains(marker) {
                i += 1
                while i < raw.count {
                    let next = raw[i]
                    let trimmed = next.trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("anchor \"\(anchorName)\"")
                        || next.hasPrefix("load anchor \"\(anchorName)\"")
                        || trimmed.isEmpty
                    {
                        i += 1
                        if next.hasPrefix("load anchor \"\(anchorName)\"") { break }
                        continue
                    }
                    break
                }
                continue
            }
            filtered.append(line)
            i += 1
        }

        conf = filtered.joined(separator: "\n")
        try conf.write(toFile: pfConfPath, atomically: true, encoding: .utf8)
        _ = try? run("/sbin/pfctl", ["-f", pfConfPath])
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: anchorPath)
            && ((try? String(contentsOfFile: pfConfPath, encoding: .utf8))?.contains(marker) == true)
    }

    static func flushDNS() throws {
        _ = try? run("/usr/bin/dscacheutil", ["-flushcache"])
        _ = try? run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "SpoofDPIHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: out.isEmpty ? "Command failed" : out]
            )
        }
        return out
    }
}

final class HelperXPCDelegate: NSObject, NSXPCListenerDelegate, SpoofDPIHelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: SpoofDPIHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func installQuicBlock(reply: @escaping (Bool, String) -> Void) {
        do {
            try QuicBlockEngine.install()
            reply(true, "installed")
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func removeQuicBlock(reply: @escaping (Bool, String) -> Void) {
        do {
            try QuicBlockEngine.remove()
            reply(true, "removed")
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func quicBlockStatus(reply: @escaping (Bool, String) -> Void) {
        let enabled = QuicBlockEngine.isInstalled()
        reply(enabled, enabled ? "enabled" : "disabled")
    }

    func flushDNS(reply: @escaping (Bool, String) -> Void) {
        do {
            try QuicBlockEngine.flushDNS()
            reply(true, "flushed")
        } catch {
            reply(false, error.localizedDescription)
        }
    }
}

@objc protocol SpoofDPIHelperProtocol {
    func installQuicBlock(reply: @escaping (Bool, String) -> Void)
    func removeQuicBlock(reply: @escaping (Bool, String) -> Void)
    func quicBlockStatus(reply: @escaping (Bool, String) -> Void)
    func flushDNS(reply: @escaping (Bool, String) -> Void)
}
