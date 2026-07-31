import Foundation

enum ShellError: LocalizedError {
    case nonZeroExit(command: String, code: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let command, let code, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(command) failed (\(code))"
            }
            return "\(command) failed (\(code)): \(detail)"
        }
    }
}

enum Shell {
    @discardableResult
    static func run(
        _ launchPath: String,
        arguments: [String],
        throwOnError: Bool = true
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let combined = String(data: outData + errData, encoding: .utf8) ?? ""

        if throwOnError, process.terminationStatus != 0 {
            throw ShellError.nonZeroExit(
                command: ([launchPath] + arguments).joined(separator: " "),
                code: process.terminationStatus,
                output: combined
            )
        }
        return combined
    }

    @discardableResult
    static func runAsync(
        _ launchPath: String,
        arguments: [String],
        throwOnError: Bool = true
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Shell.run(launchPath, arguments: arguments, throwOnError: throwOnError)
        }.value
    }
}
