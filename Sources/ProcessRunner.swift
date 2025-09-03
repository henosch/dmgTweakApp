import Foundation

// ======================================================================

// MARK: - Process Runner

// ======================================================================

struct ProcessResult {
    let stdOut: String
    let stdErr: String
    let terminationStatus: Int32
}

func runProcess(launchPath: String, arguments: [String], stdinData: Data? = nil) async throws -> ProcessResult {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var inputPipe: Pipe?
        if stdinData != nil {
            inputPipe = Pipe()
            process.standardInput = inputPipe
        }

        process.terminationHandler = { process in
            let stdOutData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let stdErrData = errPipe.fileHandleForReading.readDataToEndOfFile()

            let result = ProcessResult(
                stdOut: String(data: stdOutData, encoding: .utf8) ?? "",
                stdErr: String(data: stdErrData, encoding: .utf8) ?? "",
                terminationStatus: process.terminationStatus
            )
            continuation.resume(returning: result)
        }

        do {
            try process.run()

            if let stdinData, let inputPipe {
                inputPipe.fileHandleForWriting.write(stdinData)
                inputPipe.fileHandleForWriting.closeFile()
            }
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

func runProcessSync(launchPath: String, arguments: [String], stdinData: Data? = nil) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    var inputPipe: Pipe?
    if stdinData != nil {
        inputPipe = Pipe()
        process.standardInput = inputPipe
    }

    try process.run()

    if let stdinData, let inputPipe {
        inputPipe.fileHandleForWriting.write(stdinData)
        inputPipe.fileHandleForWriting.closeFile()
    }

    process.waitUntilExit()

    return ProcessResult(
        stdOut: String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        stdErr: String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
        terminationStatus: process.terminationStatus
    )
}
