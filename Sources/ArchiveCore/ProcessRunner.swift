import Foundation

/// A runner belongs to one operation. Cancellation also stops multi-step TAR workflows.
public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if let running, running.isRunning { running.terminate() }
    }

    public func checkCancellation() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw ArchiveError.cancelled }
    }

    public func run(_ executable: URL, arguments: [String], directory: URL? = nil, input: Data? = nil) throws -> String {
        try checkCancellation()
        let task = Process()
        let pipe = Pipe()
        task.executableURL = executable
        task.arguments = arguments
        task.currentDirectoryURL = directory
        let inputPipe = input == nil ? nil : Pipe()
        task.standardInput = inputPipe ?? FileHandle.nullDevice as Any
        task.standardOutput = pipe
        task.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        task.environment = environment
        lock.lock()
        if cancelled { lock.unlock(); throw ArchiveError.cancelled }
        do { try task.run(); process = task; lock.unlock() }
        catch { lock.unlock(); throw error }
        if let input, let inputPipe {
            // Password input is bounded by ArchiveEngine, so it fits in the pipe.
            try? inputPipe.fileHandleForWriting.write(contentsOf: input)
            try? inputPipe.fileHandleForWriting.close()
        }
        // Drain while the child runs: large listings must not fill the pipe and deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        lock.lock(); process = nil; lock.unlock()
        try checkCancellation()
        let output = String(decoding: data, as: UTF8.self)
        guard task.terminationStatus == 0 else {
            let lower = output.lowercased()
            if lower.contains("password") || lower.contains("encrypted archive") {
                throw ArchiveError.passwordRequired
            }
            let detail = output.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }.suffix(12).joined(separator: "\n")
            throw ArchiveError.engine(detail.isEmpty ? "Код ошибки \(task.terminationStatus)" : detail)
        }
        return output
    }
}
