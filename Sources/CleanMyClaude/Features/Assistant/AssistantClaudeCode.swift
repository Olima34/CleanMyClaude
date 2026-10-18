import Foundation
import AppKit

/// Bridge to Claude Code installed on the Mac: the assistant runs on the user's Claude subscription, without an API key
/// (same approach as the Vigie app). Claude Code ships with the Claude desktop app
/// (~/Library/Application Support/Claude/claude-code/<version>/…/claude) or is installed separately (`claude`).
/// It is called non-interactively (`-p`) and restricted: no session kept, no user settings, skills or MCP servers loaded,
/// no tools at all, and an answer forced into a JSON schema. The login happens once: `claude auth login --claudeai`.
enum AssistantClaudeCode {
    struct Status: Equatable {
        var binary: String?
        var loggedIn = false
        var email: String?
        var method: String?

        var available: Bool { binary != nil }
    }

    struct Answer {
        var text: String
        var actions: [(id: String, reason: String)]
        var model: String?
        var tokens: Int
    }

    enum Failure: LocalizedError {
        case notInstalled, notConnected, quota(String), timeout, failed(String), unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Claude Code est introuvable : installe ou ouvre l'app Claude, qui l'embarque."
            case .notConnected: return "Claude Code n'est pas connecté à ton abonnement : clique sur « Connecter Claude »."
            case .quota(let m): return "La limite d'usage de ton abonnement Claude est atteinte pour le moment. (\(m))"
            case .timeout: return "Claude n'a pas répondu à temps. Réessaie, ou pose une question plus courte."
            case .failed(let m): return "Claude Code : \(m)"
            case .unreadable(let m): return "Réponse illisible de Claude Code : \(m)"
            }
        }
    }

    /// Model aliases of Claude Code (always the latest version of each family).
    static func alias(for choice: AssistantModelChoice) -> String {
        switch choice {
        case .opus: return "opus"
        case .sonnet: return "sonnet"
        case .haiku: return "haiku"
        case .fable: return "fable"
        }
    }

    private static let appDir = FS.home + "/Library/Application Support/Claude/claude-code"
    private static let standalone = [FS.home + "/.local/bin/claude", FS.home + "/.claude/local/claude",
                                     "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    /// The most recent Claude Code: the one of the Claude app (updated with it), else a separate install.
    static func findBinary() -> String? {
        var bundled: [(version: [Int], path: String)] = []
        for version in FS.children(appDir) {
            let parts = version.split(separator: ".").compactMap { Int($0) }
            guard !parts.isEmpty else { continue }
            for build in FS.children(appDir + "/" + version) {
                let p = "\(appDir)/\(version)/\(build)/claude.app/Contents/MacOS/claude"
                if Shell.exists(p) { bundled.append((parts, p)) }
            }
        }
        if let best = bundled.max(by: { $0.version.lexicographicallyPrecedes($1.version) }) { return best.path }
        return standalone.first(where: Shell.exists) ?? Shell.which("claude")
    }

    /// A neutral environment: nothing inherited from a running Claude Code session (host tokens, nested-session guards)
    /// nor any API key, so the subscription is what gets used.
    static func cleanEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            !(key.hasPrefix("CLAUDE") || key.hasPrefix("ANTHROPIC_") || key.hasPrefix("MCP_"))
        }
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["LANG"] = env["LANG"] ?? "fr_FR.UTF-8"
        return env
    }

    /// `claude auth status` reads the login without using any of the subscription. Off the main thread.
    static func status() -> Status {
        guard let binary = findBinary() else { return Status() }
        let r = Shell.run(binary, ["auth", "status", "--json"], replaceEnvironment: cleanEnvironment(),
                          workingDirectory: workDir(), timeout: 30)
        guard let data = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Status(binary: binary)
        }
        return Status(binary: binary, loggedIn: json["loggedIn"] as? Bool ?? false,
                      email: json["email"] as? String, method: json["authMethod"] as? String)
    }

    /// Opens a Terminal window running `claude auth login --claudeai`; the user approves in the browser.
    @discardableResult
    static func connect() -> String {
        guard let binary = findBinary() else { return Failure.notInstalled.localizedDescription }
        guard let folder = DataStore.ensureFolder() else { return "Mode démo : rien n'est lancé." }
        let quoted = "'" + binary.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = [
            "#!/bin/zsh",
            "echo \"Clean My Claude : connexion de Claude Code à ton abonnement Claude (une seule fois).\"",
            "echo \"Une page s'ouvre dans le navigateur : connecte-toi avec ton compte Claude et autorise.\"",
            "echo \"\"",
            "unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN",
            "\(quoted) auth login --claudeai",
            "echo \"\"",
            "echo \"Terminé : reviens dans Clean My Claude et clique sur « J'ai terminé la connexion ».\"",
            "read -k 1 \"?Appuie sur une touche pour fermer cette fenêtre.\"",
            ""
        ].joined(separator: "\n")
        let url = folder.appendingPathComponent("connecter-claude.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            return "Impossible de préparer la connexion : \(error.localizedDescription)"
        }
        NSWorkspace.shared.open(url)
        return "Terminal ouvert : valide la connexion dans le navigateur, puis reviens ici."
    }

    /// Outside any project: no CLAUDE.md nor settings get loaded.
    private static func workDir() -> String {
        let dir = NSTemporaryDirectory() + "cleanmyclaude-claude"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    /// One request. Off the main thread: it may take a minute.
    static func ask(system: String, prompt: String, schema: [String: Any], model: AssistantModelChoice,
                    effort: String = "medium", timeout: TimeInterval = 300) throws -> Answer {
        guard let binary = findBinary() else { throw Failure.notInstalled }
        let schemaText = String(data: (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? Data(),
                                encoding: .utf8) ?? "{}"
        var args = [
            "-p", "--output-format", "stream-json", "--verbose", "--no-session-persistence", "--restricted",
            "--permission-mode", "dontAsk", "--strict-mcp-config", "--disable-slash-commands",
            "--system-prompt", system, "--tools", "", "--max-turns", "3",
            "--json-schema", schemaText, "--model", alias(for: model)
        ]
        if model != .haiku { args += ["--effort", effort] } // Haiku does not take an effort level here
        let r = Shell.run(binary, args, replaceEnvironment: cleanEnvironment(), input: prompt,
                          workingDirectory: workDir(), timeout: timeout)
        if r.status == 15 || r.status == 9 { throw Failure.timeout }
        return try parse(r.out, stderr: r.err)
    }

    /// Reads the `stream-json` output: the final `result` event carries the structured answer.
    static func parse(_ stdout: String, stderr: String = "") throws -> Answer {
        var result: [String: Any]?
        for line in stdout.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if event["type"] as? String == "result" { result = event }
        }
        guard let data = result else {
            throw Failure.unreadable(String((stderr.isEmpty ? stdout : stderr).suffix(300)))
        }
        if data["is_error"] as? Bool == true || (data["subtype"] as? String ?? "success") != "success" {
            let message = (data["result"] as? String) ?? (data["subtype"] as? String) ?? "erreur"
            let lower = message.lowercased()
            if lower.contains("authenticat") || lower.contains("login") || lower.contains("log in") { throw Failure.notConnected }
            if lower.range(of: #"session limit|usage limit|rate limit|limit reached"#, options: .regularExpression) != nil {
                throw Failure.quota(String(message.prefix(120)))
            }
            throw Failure.failed(String(message.prefix(300)))
        }
        var structured = data["structured_output"] as? [String: Any]
        if structured == nil, let text = data["result"] as? String {
            structured = extractJSON(text)
        }
        let usage = data["usage"] as? [String: Any] ?? [:]
        let tokens = ["input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
            .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
        let modelUsage = data["modelUsage"] as? [String: Any] ?? [:]
        let writer = modelUsage.max { a, b in
            ((a.value as? [String: Any])?["outputTokens"] as? Int ?? 0) < ((b.value as? [String: Any])?["outputTokens"] as? Int ?? 0)
        }?.key
        guard let s = structured else {
            // No structured answer: show the text as is.
            return Answer(text: data["result"] as? String ?? "", actions: [], model: writer, tokens: tokens)
        }
        let actions = (s["actions"] as? [[String: Any]] ?? []).compactMap { a -> (String, String)? in
            guard let id = a["command_id"] as? String else { return nil }
            return (id, a["reason"] as? String ?? "")
        }
        return Answer(text: s["reponse"] as? String ?? "", actions: actions, model: writer, tokens: tokens)
    }

    /// The first {...} object of a text.
    static func extractJSON(_ text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The answer's shape: markdown text plus up to three commands of the catalogue.
    static func schema(commandIDs: [String]) -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "reponse": ["type": "string", "description": "La réponse à l'utilisateur, en français, en Markdown léger."],
                "actions": [
                    "type": "array",
                    "maxItems": 3,
                    "description": "0 à 3 commandes de Clean My Claude à proposer sous forme de boutons.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "command_id": ["type": "string", "enum": commandIDs],
                            "reason": ["type": "string", "description": "Pourquoi cette commande aide, en une phrase."]
                        ],
                        "required": ["command_id", "reason"],
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "required": ["reponse", "actions"],
            "additionalProperties": false
        ]
    }
}
