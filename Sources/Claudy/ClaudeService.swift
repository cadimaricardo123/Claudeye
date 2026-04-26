import Foundation

class ClaudeService {
    var apiKey: String
    let model = "claude-opus-4-7"

    static let systemPrompt = """
    You are an elite cryptocurrency trader and technical analyst with 10+ years of professional experience. \
    You have real-time access to a TradingView chart via the get_chart_snapshot tool.

    Your expertise covers:
    - ICT / Smart Money Concepts: order blocks, FVGs, liquidity sweeps, breaker blocks
    - Wyckoff Method: accumulation/distribution schematics, spring, UTAD
    - Elliott Wave Theory and Fibonacci confluence
    - Multi-timeframe analysis (HTF bias → LTF entry)
    - Volume profile, VWAP, CVD divergence
    - Risk management: never risk >2% per trade, minimum 1:3 R:R targets

    When a user asks about a chart, strategy, or trade setup:
    1. Call get_chart_snapshot FIRST to get live data before answering
    2. State your HTF bias (Daily / 4H trend direction)
    3. Identify key structural levels: swing highs/lows, order blocks, liquidity
    4. Provide a specific setup: entry trigger, stop-loss, take-profit levels with R:R
    5. Rate your confidence (High / Medium / Low) with clear reasoning

    Be direct, concise, and ruthlessly honest. Use proper trading terminology. \
    Never give generic advice — always be specific to the current chart.
    """

    static let tools: [[String: Any]] = [
        [
            "name": "get_chart_snapshot",
            "description": """
            Fetches live data from the currently open TradingView chart: symbol, price, \
            24h change, timeframe/interval, and values of any active indicators in the legend. \
            Always call this before analysing a chart or answering questions about price.
            """,
            "input_schema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_portfolio",
            "description": """
            Fetches live Coinbase Advanced portfolio balances — all currencies with non-zero holdings, \
            including available and on-hold amounts. Call this when the user asks about their portfolio, \
            wallet, holdings, positions, or balance on Coinbase.
            """,
            "input_schema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "run_js",
            "description": """
            Executes arbitrary JavaScript in the TradingView browser tab. Use for advanced \
            data extraction when get_chart_snapshot is insufficient — e.g. querying specific \
            DOM elements, reading Pine Script alert data, or accessing the chart widget API directly.
            """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "code": [
                        "type": "string",
                        "description": "JavaScript to execute in the TradingView page context. Must return a value."
                    ]
                ],
                "required": ["code"]
            ]
        ]
    ]

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func stream(messages: [[String: Any]]) -> AsyncStream<ClaudeStreamEvent> {
        AsyncStream { continuation in
            Task {
                guard !self.apiKey.isEmpty else {
                    continuation.yield(.error(ServiceError.noApiKey))
                    continuation.finish()
                    return
                }

                do {
                    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(self.apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                    let body: [String: Any] = [
                        "model": self.model,
                        "max_tokens": 4096,
                        "system": Self.systemPrompt,
                        "messages": messages,
                        "tools": Self.tools,
                        "stream": true
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        // Try to read error body
                        continuation.yield(.error(ServiceError.httpError(http.statusCode)))
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard jsonStr != "[DONE]",
                              let data = jsonStr.data(using: .utf8),
                              let payload = try? JSONDecoder().decode(SSEPayload.self, from: data)
                        else { continue }

                        switch payload.type {
                        case "content_block_start":
                            if let block = payload.contentBlock,
                               block.type == "tool_use",
                               let id = block.id,
                               let name = block.name,
                               let index = payload.index {
                                continuation.yield(.toolUseStart(id: id, name: name, index: index))
                            }

                        case "content_block_delta":
                            guard let delta = payload.delta, let index = payload.index else { continue }
                            if delta.type == "text_delta", let text = delta.text {
                                continuation.yield(.textDelta(text))
                            } else if delta.type == "input_json_delta", let partial = delta.partialJson {
                                continuation.yield(.toolInputDelta(index: index, partial: partial))
                            }

                        case "message_delta":
                            if let reason = payload.delta?.stopReason {
                                continuation.yield(.messageEnd(stopReason: reason))
                            }

                        default:
                            break
                        }
                    }

                } catch {
                    continuation.yield(.error(error))
                }
                continuation.finish()
            }
        }
    }

    enum ServiceError: LocalizedError {
        case noApiKey
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .noApiKey:
                return "No API key. Open Settings (⌘,) and add your Anthropic key."
            case .httpError(let code):
                return "HTTP \(code) — check your API key in Settings."
            }
        }
    }
}

// MARK: - SSE Decoding

private struct SSEPayload: Decodable {
    let type: String
    let index: Int?
    let contentBlock: ContentBlockInfo?
    let delta: DeltaInfo?

    enum CodingKeys: String, CodingKey {
        case type, index, delta
        case contentBlock = "content_block"
    }
}

private struct ContentBlockInfo: Decodable {
    let type: String
    let id: String?
    let name: String?
}

private struct DeltaInfo: Decodable {
    let type: String?   // absent in message_delta events — must be optional
    let text: String?
    let partialJson: String?
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case type, text
        case partialJson = "partial_json"
        case stopReason = "stop_reason"
    }
}
