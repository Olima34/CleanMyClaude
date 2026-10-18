import Foundation
import AppKit

/// Runs command line tools and AppleScript.
enum Shell {
    struct Output {
        var status: Int32
        var out: String
        var err: String
        var ok: Bool { status == 0 }
        /// stdout and stderr together (some tools such as sysadminctl answer on stderr).
        var all: String { out + err }
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    /// Runs a tool and waits for it, killing it after `timeout` seconds.
    static func run(_ path: String, _ args: [String] = [], timeout: TimeInterval = 20) -> Output {
        if DemoData.isEnabled { return Output(status: -1, out: "", err: DemoData.refusal) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return Output(status: -1, out: "", err: error.localizedDescription)
        }
        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        killer.cancel()
        return Output(status: p.terminationStatus,
                      out: String(decoding: outData, as: UTF8.self),
                      err: String(decoding: errBox.data, as: UTF8.self))
    }

    /// Runs a command line through /bin/sh.
    static func sh(_ command: String, timeout: TimeInterval = 20) -> Output {
        run("/bin/sh", ["-c", command], timeout: timeout)
    }

    private static let scriptQueue = DispatchQueue(label: "cleanmyclaude.applescript")

    /// Runs a command as administrator. macOS shows its own password dialog: the app never sees the password.
    static func runAsAdmin(_ command: String) -> Output {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return appleScript("do shell script \"\(escaped)\" with administrator privileges")
    }

    /// Runs an AppleScript (serialized: NSAppleScript is not thread safe).
    static func appleScript(_ source: String) -> Output {
        if DemoData.isEnabled { return Output(status: -1, out: "", err: DemoData.refusal) }
        return scriptQueue.sync {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? -1
                let message = error[NSAppleScript.errorMessage] as? String ?? "Erreur inconnue"
                return Output(status: Int32(code), out: "", err: code == -128 ? "Opération annulée." : message)
            }
            return Output(status: 0, out: result?.stringValue ?? "", err: "")
        }
    }

    static func exists(_ tool: String) -> Bool { FileManager.default.isExecutableFile(atPath: tool) }
}
