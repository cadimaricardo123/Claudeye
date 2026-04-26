import Foundation

// MARK: - Chat

struct ChatMessage: Identifiable {
    let id: UUID
    var role: Role
    var content: String
    var isStreaming: Bool
    let timestamp: Date

    enum Role { case user, assistant }

    init(role: Role, content: String, isStreaming: Bool = false) {
        id = UUID()
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        timestamp = Date()
    }
}

// MARK: - Chart

struct ChartSnapshot {
    var symbol: String = "—"
    var price: String = "—"
    var change: String = "—"
    var changePercent: String = "—"
    var interval: String = "—"
    var volume: String = "—"
    var indicators: [String: String] = [:]
    var fetchedAt: Date?

    func formatted() -> String {
        var lines = [
            "Symbol: \(symbol)",
            "Price: \(price)",
        ]
        if change != "—" { lines.append("Change: \(change) (\(changePercent))") }
        if interval != "—" { lines.append("Interval: \(interval)") }
        if volume != "—" { lines.append("Volume: \(volume)") }
        if !indicators.isEmpty {
            lines.append("Active indicators:")
            for key in indicators.keys.sorted() {
                lines.append("  \(key): \(indicators[key]!)")
            }
        }
        if fetchedAt == nil { return "TradingView not connected." }
        return lines.joined(separator: "\n")
    }
}

// MARK: - CDP

struct CDPTarget: Codable {
    let id: String
    let title: String
    let url: String
    let type: String
    let webSocketDebuggerUrl: String?
}

struct CDPResponse: Codable {
    let id: Int?
    let result: CDPResult?
    let error: CDPError?
}

struct CDPResult: Codable {
    let result: CDPRemoteObject?
}

struct CDPRemoteObject: Codable {
    let type: String?
    let value: String?
}

struct CDPError: Codable {
    let code: Int
    let message: String
}

// MARK: - Tool

struct ToolCall {
    let id: String
    let name: String
    var inputJSON: String = ""
}

// MARK: - Stream Events

enum ClaudeStreamEvent {
    case textDelta(String)
    case toolUseStart(id: String, name: String, index: Int)
    case toolInputDelta(index: Int, partial: String)
    case messageEnd(stopReason: String)
    case error(Error)
}
