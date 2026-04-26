import Foundation
import CryptoKit

// MARK: - Models

struct CBAccountsResponse: Decodable {
    let accounts: [CBAccount]
    let hasNext: Bool?
    let cursor: String?

    enum CodingKeys: String, CodingKey {
        case accounts
        case hasNext = "has_next"
        case cursor
    }
}

struct CBAccount: Decodable, Identifiable {
    let uuid: String
    let name: String
    let currency: String
    let availableBalance: CBBalance
    let hold: CBBalance

    var id: String { uuid }
    var availableDouble: Double { Double(availableBalance.value) ?? 0 }
    var holdDouble: Double      { Double(hold.value) ?? 0 }
    var totalDouble: Double     { availableDouble + holdDouble }

    enum CodingKeys: String, CodingKey {
        case uuid, name, currency
        case availableBalance = "available_balance"
        case hold
    }
}

struct CBBalance: Decodable {
    let value: String
    let currency: String
}

// MARK: - Models (Primary / v2)

struct CBPrimaryAccountsResponse: Decodable {
    let data: [CBPrimaryAccount]
}

struct CBPrimaryAccount: Decodable, Identifiable {
    let id: String
    let name: String
    let currency: CBPrimaryCurrency
    let balance: CBPrimaryBalance

    var balanceDouble: Double { Double(balance.amount) ?? 0 }
}

struct CBPrimaryCurrency: Decodable { let code: String }
struct CBPrimaryBalance:  Decodable { let amount: String; let currency: String }

// MARK: - Service

@MainActor
class CoinbaseService: ObservableObject {
    // Perpetual (Advanced Trade)
    @Published var accounts: [CBAccount] = []
    @Published var isConnected = false
    @Published var statusMessage = "Not connected"

    // Primary wallet (v3 brokerage with separate key)
    @Published var primaryAccounts: [CBPrimaryAccount] = []
    @Published var isPrimaryConnected = false
    @Published var primaryStatusMessage = "Not connected"

    // Perpetual CDP key
    var apiKeyName: String = ""
    var privateKeyPEM: String = ""

    // Primary wallet CDP key (same format, different values)
    var primaryApiKeyName: String = ""
    var primaryPrivateKeyPEM: String = ""

    // MARK: - Perpetual wallet

    func connect() async {
        statusMessage = "Connecting…"
        do {
            try await fetchAccounts()
            isConnected = true
            statusMessage = "Connected — \(accounts.count) account\(accounts.count == 1 ? "" : "s")"
        } catch {
            isConnected = false
            statusMessage = error.localizedDescription
        }
    }

    func disconnect() {
        accounts = []
        isConnected = false
        statusMessage = "Not connected"
    }

    // MARK: - Primary wallet

    func connectPrimary() async {
        primaryStatusMessage = "Connecting…"
        do {
            try await fetchPrimaryAccounts()
            isPrimaryConnected = true
            primaryStatusMessage = "Connected — \(primaryAccounts.count) account\(primaryAccounts.count == 1 ? "" : "s")"
        } catch {
            isPrimaryConnected = false
            primaryStatusMessage = error.localizedDescription
        }
    }

    func disconnectPrimary() {
        primaryAccounts = []
        isPrimaryConnected = false
        primaryStatusMessage = "Not connected"
    }

    func refreshPrimary() async {
        do { try await fetchPrimaryAccounts() } catch {}
    }

    func refresh() async {
        do { try await fetchAccounts() } catch {}
        if isPrimaryConnected { do { try await fetchPrimaryAccounts() } catch {} }
    }

    func portfolioSummary() -> String {
        var lines: [String] = []

        if isConnected, !accounts.isEmpty {
            lines.append("Coinbase Perpetual portfolio:")
            for acc in accounts.sorted(by: { $0.totalDouble > $1.totalDouble }) {
                var line = "  \(acc.currency): \(fmt(acc.availableBalance.value))"
                if acc.holdDouble > 0 { line += " (on hold: \(fmt(acc.hold.value)))" }
                lines.append(line)
            }
        } else {
            lines.append("Coinbase Perpetual: not connected. Add perpetual CDP key in Settings (⌘,).")
        }

        lines.append("")

        if isPrimaryConnected, !primaryAccounts.isEmpty {
            lines.append("Coinbase Primary portfolio:")
            let nonZero = primaryAccounts.filter { $0.balanceDouble > 0 }
                                         .sorted { $0.balanceDouble > $1.balanceDouble }
            for acc in nonZero {
                lines.append("  \(acc.currency.code): \(fmt(acc.balance.amount))")
            }
        } else {
            lines.append("Coinbase Primary: not connected. Add primary CDP key in Settings (⌘,).")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Networking

    private func fetchAccounts() async throws {
        var all: [CBAccount] = []
        var cursor: String? = nil

        repeat {
            var path = "/api/v3/brokerage/accounts?limit=250"
            if let c = cursor { path += "&cursor=\(c)" }
            let (data, _) = try await signedGET(path)
            let decoded = try JSONDecoder().decode(CBAccountsResponse.self, from: data)
            all.append(contentsOf: decoded.accounts)
            cursor = (decoded.hasNext == true) ? decoded.cursor : nil
        } while cursor != nil

        accounts = all.filter { $0.totalDouble > 0 }
    }

    private func fetchPrimaryAccounts() async throws {
        guard !primaryApiKeyName.isEmpty, !primaryPrivateKeyPEM.isEmpty else {
            throw CBError.noPrimaryCredentials
        }
        var all: [CBPrimaryAccount] = []
        var nextPath: String? = "/v2/accounts?limit=100"

        while let path = nextPath {
            let (data, _) = try await signedPrimaryGET(path)
            let decoded = try JSONDecoder().decode(CBPrimaryAccountsResponse.self, from: data)
            all.append(contentsOf: decoded.data)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let pagination = json["pagination"] as? [String: Any],
               let next = pagination["next_uri"] as? String, !next.isEmpty {
                nextPath = next
            } else {
                nextPath = nil
            }
        }

        primaryAccounts = all.filter { $0.balanceDouble > 0 }
    }

    // Perpetual wallet — signed with perpetual CDP key
    func signedGET(_ path: String) async throws -> (Data, HTTPURLResponse) {
        guard !apiKeyName.isEmpty, !privateKeyPEM.isEmpty else { throw CBError.noCredentials }
        let jwt = try makeJWT(keyName: apiKeyName, pem: privateKeyPEM, method: "GET", path: path)
        return try await performGET(path: path, jwt: jwt)
    }

    // Primary wallet — signed with primary CDP key
    func signedPrimaryGET(_ path: String) async throws -> (Data, HTTPURLResponse) {
        guard !primaryApiKeyName.isEmpty, !primaryPrivateKeyPEM.isEmpty else { throw CBError.noPrimaryCredentials }
        let jwt = try makeJWT(keyName: primaryApiKeyName, pem: primaryPrivateKeyPEM, method: "GET", path: path)
        return try await performGET(path: path, jwt: jwt)
    }

    private func performGET(path: String, jwt: String) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: URL(string: "https://api.coinbase.com" + path)!)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)",    forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CBError.badResponse }

        if http.statusCode != 200 {
            let msg = apiErrorMessage(data) ?? "HTTP \(http.statusCode)"
            throw CBError.apiError(msg)
        }
        return (data, http)
    }

    // MARK: - JWT (ES256 / CDP)

    private func loadPrivateKey(from pem: String) throws -> P256.Signing.PrivateKey {
        // Normalise: handle literal \n sequences (from JSON exports), CR/CRLF, and trim
        var pem = pem
            .replacingOccurrences(of: "\\n", with: "\n")   // literal backslash-n → real newline
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If there are no newlines at all, try to reconstruct PEM with 64-char line wrapping
        if !pem.contains("\n") {
            let header = "-----BEGIN EC PRIVATE KEY-----"
            let footer = "-----END EC PRIVATE KEY-----"
            let altHeader = "-----BEGIN PRIVATE KEY-----"
            let altFooter = "-----END PRIVATE KEY-----"
            for (h, f) in [(header, footer), (altHeader, altFooter)] {
                if pem.hasPrefix(h), pem.hasSuffix(f) {
                    let inner = pem.dropFirst(h.count).dropLast(f.count)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let wrapped = stride(from: 0, to: inner.count, by: 64)
                        .map { i -> String in
                            let start = inner.index(inner.startIndex, offsetBy: i)
                            let end   = inner.index(start, offsetBy: min(64, inner.count - i))
                            return String(inner[start..<end])
                        }.joined(separator: "\n")
                    pem = "\(h)\n\(wrapped)\n\(f)"
                    break
                }
            }
        }

        // Attempt 1: direct PEM parse (SEC1 or PKCS#8)
        if let k = try? P256.Signing.PrivateKey(pemRepresentation: pem) { return k }

        // Strip PEM headers and base64-decode to DER
        let b64 = pem.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()
        guard let der = Data(base64Encoded: b64, options: .ignoreUnknownCharacters), !der.isEmpty else {
            throw CBError.invalidKey("Cannot decode PEM base64 — paste the full key block including -----BEGIN/END----- lines")
        }

        // Attempt 2: DER (handles PKCS#8 wrapped keys)
        if let k = try? P256.Signing.PrivateKey(derRepresentation: der) { return k }

        // Attempt 3: scan DER for raw 32-byte EC private key (OCTET STRING 0x04 0x20 ...)
        let bytes = [UInt8](der)
        let limit = bytes.count > 33 ? bytes.count - 33 : 0
        for i in 0..<limit {
            if bytes[i] == 0x04, bytes[i + 1] == 0x20 {
                let raw = Data(bytes[(i + 2)..<(i + 34)])
                if let k = try? P256.Signing.PrivateKey(rawRepresentation: raw) { return k }
            }
        }

        // Attempt 4: maybe the whole DER payload IS the raw 32-byte key
        if der.count == 32, let k = try? P256.Signing.PrivateKey(rawRepresentation: der) { return k }

        throw CBError.invalidKey("Decoded \(der.count) bytes but no valid P-256 key found — make sure you pasted the EC private key (not the API secret)")
    }

    private func makeJWT(keyName: String, pem: String, method: String, path: String) throws -> String {
        let privKey = try loadPrivateKey(from: pem)

        let now       = Int(Date().timeIntervalSince1970)
        let cleanPath = path.components(separatedBy: "?")[0]
        let uri       = "\(method) api.coinbase.com\(cleanPath)"

        let header: [String: Any] = [
            "alg":   "ES256",
            "kid":   keyName,
            "typ":   "JWT",
            "nonce": String(UInt64.random(in: 1...UInt64.max))
        ]
        let claims: [String: Any] = [
            "sub": keyName,
            "iss": "cdp",
            "nbf": now,
            "exp": now + 120,
            "uri": uri
        ]

        let h = b64url(try JSONSerialization.data(withJSONObject: header))
        let c = b64url(try JSONSerialization.data(withJSONObject: claims))
        let msg = "\(h).\(c)"

        // ES256: CryptoKit hashes with SHA-256 internally
        let sig = try privKey.signature(for: Data(msg.utf8))
        return "\(msg).\(b64url(sig.rawRepresentation))"
    }

    private func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .init(charactersIn: "="))
    }

    private func apiErrorMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["message"] as? String ?? json["error"] as? String
    }

    private func fmt(_ value: String) -> String {
        guard let d = Double(value), d != 0 else { return value }
        return d >= 1 ? String(format: "%.4f", d) : String(format: "%.8f", d)
    }

    // MARK: - Errors

    enum CBError: LocalizedError {
        case noCredentials, noPrimaryCredentials, badResponse
        case apiError(String)
        case invalidKey(String)

        var errorDescription: String? {
            switch self {
            case .noCredentials:         return "Coinbase perpetual credentials not set — add them in Settings (⌘,)"
            case .noPrimaryCredentials:  return "Coinbase primary wallet credentials not set — add them in Settings (⌘,)"
            case .badResponse:           return "Invalid response from Coinbase"
            case .apiError(let m):       return m
            case .invalidKey(let m):     return "Invalid key: \(m)"
            }
        }
    }
}
