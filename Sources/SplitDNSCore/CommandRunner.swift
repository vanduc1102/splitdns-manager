import Foundation

struct CommandResult: Equatable, Sendable {
    var status: Int32
    var standardOutput: String
    var standardError: String
}

enum CommandError: LocalizedError, Equatable {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            message.isEmpty ? "The command failed." : message
        }
    }
}

protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult
}

/// Runs an executable directly (no shell) and terminates it if the calling task is cancelled.
struct ProcessCommandRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        let job = ProcessJob(executable: executable, arguments: arguments)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Blocking on the child process must not tie up the cooperative thread pool.
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result(catching: job.run))
                }
            }
        } onCancel: {
            job.cancel()
        }
    }
}

private final class ProcessJob: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private var isCancelled = false

    init(executable: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            if process.isRunning {
                process.terminate()
            }
        }
    }

    func run() throws -> CommandResult {
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try lock.withLock {
            guard !isCancelled else { throw CancellationError() }
            try process.run()
        }

        // Both pipes are drained concurrently so a chatty process can never fill one and block.
        let readers = DispatchGroup()
        let output = OutputCollector()
        let error = OutputCollector()
        drain(outputPipe.fileHandleForReading, into: output, group: readers)
        drain(errorPipe.fileHandleForReading, into: error, group: readers)
        finished.wait()
        readers.wait()

        if lock.withLock({ isCancelled }) {
            throw CancellationError()
        }
        return CommandResult(
            status: process.terminationStatus,
            standardOutput: output.text,
            standardError: error.text
        )
    }

    private func drain(_ handle: FileHandle, into collector: OutputCollector, group: DispatchGroup) {
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            collector.store((try? handle.readToEnd()) ?? Data())
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var text: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }

    func store(_ newData: Data) {
        lock.withLock { data = newData }
    }
}
