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

    /// The environment of child processes. Apps opened from the Finder start with a bare PATH:
    /// Homebrew's folders are added so `brew`, `mas` or `ffmpeg` are found.
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin"]
        let current = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        env["PATH"] = (current + extra.filter { !current.contains($0) }).joined(separator: ":")
        env["LANG"] = env["LANG"] ?? "fr_FR.UTF-8"
        return env
    }()

    /// Full path of a command line tool, looked up in `environment`'s PATH.
    static func which(_ tool: String) -> String? {
        if tool.hasPrefix("/") { return exists(tool) ? tool : nil }
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            let p = "\(dir)/\(tool)"
            if exists(p) { return p }
        }
        return nil
    }

    /// Runs a tool and waits for it, killing it after `timeout` seconds.
    /// `replaceEnvironment` gives the tool exactly that environment (instead of the app's plus `env`);
    /// `input` is written to its standard input.
    static func run(_ path: String, _ args: [String] = [], env: [String: String] = [:],
                    replaceEnvironment: [String: String]? = nil, input: String? = nil,
                    workingDirectory: String? = nil, timeout: TimeInterval = 20) -> Output {
        if DemoData.isEnabled { return Output(status: -1, out: "", err: DemoData.refusal) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = replaceEnvironment ?? environment.merging(env) { _, new in new }
        if let workingDirectory { p.currentDirectoryURL = URL(fileURLWithPath: workingDirectory) }
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        let inPipe = input.map { _ in Pipe() }
        p.standardInput = inPipe ?? FileHandle.nullDevice
        do { try p.run() } catch {
            return Output(status: -1, out: "", err: error.localizedDescription)
        }
        if let inPipe, let input {
            let data = Data(input.utf8)
            DispatchQueue.global(qos: .utility).async {
                try? inPipe.fileHandleForWriting.write(contentsOf: data)
                try? inPipe.fileHandleForWriting.close()
            }
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

    /// Runs a long tool (brew, networkQuality, ping…) and hands over each line of output as it comes.
    /// Returns when the tool exits or when `isCancelled` turns true (the tool is then terminated).
    /// Must not be called from the main thread.
    static func stream(_ path: String, _ args: [String] = [], env: [String: String] = [:],
                       isCancelled: @escaping () -> Bool = { false },
                       onLine: @escaping (String) -> Void) -> Output {
        if DemoData.isEnabled { return Output(status: -1, out: "", err: DemoData.refusal) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = environment.merging(env) { _, new in new }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return Output(status: -1, out: "", err: error.localizedDescription)
        }
        // A tool may stay silent until it ends (networkQuality -c): the cancel is watched apart from the output.
        let watcher = DispatchWorkItem {
            while p.isRunning {
                if isCancelled() {
                    terminateTree(p)
                    return
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        DispatchQueue.global(qos: .utility).async(execute: watcher)
        let all = Box()
        var pending = Data()
        let handle = pipe.fileHandleForReading
        while true {
            if isCancelled() {
                terminateTree(p)
                break
            }
            let chunk = handle.availableData
            if chunk.isEmpty { break } // end of file: the tool exited
            all.data.append(chunk)
            pending.append(chunk)
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...nl)
                onLine(line)
            }
        }
        if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
        p.waitUntilExit()
        watcher.cancel()
        return Output(status: p.terminationStatus, out: String(decoding: all.data, as: UTF8.self), err: "")
    }

    /// Stops a tool and the processes it started itself (brew launches ruby, curl, git…).
    private static func terminateTree(_ p: Process) {
        guard p.isRunning else { return }
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-TERM", "-P", "\(p.processIdentifier)"]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        try? pkill.run()
        pkill.waitUntilExit()
        p.terminate()
    }

    /// Starts a tool without waiting for it nor reading its output: it keeps running after the app quits
    /// (the relaunch after an update). Nothing in demo mode.
    @discardableResult
    static func launchDetached(_ path: String, _ args: [String] = []) -> Bool {
        if DemoData.isEnabled { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        return true
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
        return appleScript("do shell script \"\(escaped)\" with administrator privileges without altering line endings")
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
