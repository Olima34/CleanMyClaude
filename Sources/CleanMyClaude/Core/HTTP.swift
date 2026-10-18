import Foundation

/// The only way the app talks to the Internet. HTTPS only, never in demo mode,
/// and every host contacted is written to the action log. Call it only after a user click
/// or a setting the user turned on (the app promises nothing leaves the Mac otherwise).
enum HTTP {
    enum Failure: LocalizedError {
        case demo, insecure, status(Int), empty

        var errorDescription: String? {
            switch self {
            case .demo: return "Mode démo : aucune connexion réseau."
            case .insecure: return "Adresse refusée : seules les connexions HTTPS sont autorisées."
            case .status(let c): return "Le serveur a répondu avec le code \(c)."
            case .empty: return "Réponse vide."
            }
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": "CleanMyClaude/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (macOS)"]
        return URLSession(configuration: c)
    }()

    static func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return try await send(req)
    }

    static func post(_ url: URL, json: Data, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = json
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return try await send(req)
    }

    /// For slow answers (an AI model thinking before its first byte): five minutes instead of twenty seconds.
    private static let patientSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 300
        c.timeoutIntervalForResource = 600
        return URLSession(configuration: c)
    }()

    /// Like `send`, but hands back error responses too (their body often explains what went wrong).
    /// `patient` allows up to five minutes of silence from the server.
    static func sendKeepingErrors(_ request: URLRequest, patient: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard !DemoData.isEnabled else { throw Failure.demo }
        guard request.url?.scheme == "https" else { throw Failure.insecure }
        ActionLog.write("RÉSEAU \(request.httpMethod ?? "GET") \(request.url?.host ?? "?")")
        let (data, response) = try await (patient ? patientSession : session).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.empty }
        return (data, http)
    }

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !DemoData.isEnabled else { throw Failure.demo }
        guard request.url?.scheme == "https" else { throw Failure.insecure }
        ActionLog.write("RÉSEAU \(request.httpMethod ?? "GET") \(request.url?.host ?? "?")")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.empty }
        guard (200..<300).contains(http.statusCode) else { throw Failure.status(http.statusCode) }
        return (data, http)
    }
}
