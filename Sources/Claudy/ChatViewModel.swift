import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false

    var bridge: TradingViewBridge
    var coinbase: CoinbaseService
    var claudeService: ClaudeService

    private var apiMessages: [[String: Any]] = []

    init(bridge: TradingViewBridge, coinbase: CoinbaseService, apiKey: String = "") {
        self.bridge = bridge
        self.coinbase = coinbase
        self.claudeService = ClaudeService(apiKey: apiKey)
        messages.append(ChatMessage(
            role: .assistant,
            content: "Ready to trade. Connect TradingView in the sidebar, then ask me about the chart — setups, levels, structure, strategy."
        ))
    }

    func updateApiKey(_ key: String) {
        claudeService.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        inputText = ""
        messages.append(ChatMessage(role: .user, content: text))
        apiMessages.append(["role": "user", "content": text])

        await runAgentLoop()
    }

    func clearHistory() {
        messages.removeAll()
        apiMessages.removeAll()
        messages.append(ChatMessage(
            role: .assistant,
            content: "Conversation cleared. What's the setup?"
        ))
    }

    // MARK: - Agentic Loop

    private func runAgentLoop() async {
        isLoading = true
        defer { isLoading = false }

        // One persistent bubble for the entire agent turn — updated in place
        let msgIdx = messages.count
        messages.append(ChatMessage(role: .assistant, content: "", isStreaming: true))

        var isFirstPass = true

        while true {
            var accText = ""
            var toolCalls: [ToolCall] = []
            var toolIdxByBlockIndex: [Int: Int] = [:]
            var stopReason = "end_turn"
            var streamError: Error? = nil

            // On follow-up passes (after tool use) show a brief status while waiting for next tokens
            if !isFirstPass {
                messages[msgIdx].content = "⚙️ _Analyzing chart data…_"
            }
            isFirstPass = false

            for await event in claudeService.stream(messages: apiMessages) {
                switch event {
                case .textDelta(let t):
                    // First real text token — clear any status indicator
                    if accText.isEmpty {
                        messages[msgIdx].content = t
                    } else {
                        messages[msgIdx].content += t
                    }
                    accText += t

                case .toolUseStart(let id, let name, let index):
                    toolIdxByBlockIndex[index] = toolCalls.count
                    toolCalls.append(ToolCall(id: id, name: name))
                    messages[msgIdx].content = "⚙️ _Fetching live chart data…_"

                case .toolInputDelta(let index, let partial):
                    if let i = toolIdxByBlockIndex[index] {
                        toolCalls[i].inputJSON += partial
                    }

                case .messageEnd(let reason):
                    stopReason = reason

                case .error(let error):
                    streamError = error
                }
            }

            if let error = streamError {
                messages[msgIdx].content = "⚠️ \(error.localizedDescription)"
                messages[msgIdx].isStreaming = false
                return
            }

            // Build assistant turn for API history
            var assistantContent: [[String: Any]] = []
            if !accText.isEmpty {
                assistantContent.append(["type": "text", "text": accText])
            }
            for tc in toolCalls {
                let inputObj = parseJSON(tc.inputJSON) ?? [String: Any]()
                assistantContent.append([
                    "type": "tool_use",
                    "id": tc.id,
                    "name": tc.name,
                    "input": inputObj
                ])
            }
            if assistantContent.isEmpty {
                assistantContent.append(["type": "text", "text": ""])
            }
            apiMessages.append(["role": "assistant", "content": assistantContent])

            guard stopReason == "tool_use", !toolCalls.isEmpty else { break }

            // Execute tools — update bubble to show what we're doing
            messages[msgIdx].content = "⚙️ _Reading TradingView chart…_"
            var toolResults: [[String: Any]] = []
            for tc in toolCalls {
                let result = await executeTool(tc)
                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": tc.id,
                    "content": result
                ])
            }
            apiMessages.append(["role": "user", "content": toolResults])
        }

        messages[msgIdx].isStreaming = false

        let finalContent = messages[msgIdx].content.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalContent.isEmpty || finalContent.hasPrefix("⚙️ _") {
            messages[msgIdx].content = "⚠️ No response received. Check your API key in Settings (⌘,)."
            if !apiMessages.isEmpty { apiMessages.removeLast() }
        }
    }

    // MARK: - Tool Execution

    private func executeTool(_ tool: ToolCall) async -> String {
        switch tool.name {
        case "get_chart_snapshot":
            let snap = await bridge.fetchSnapshot()
            return snap.formatted()

        case "get_portfolio":
            return coinbase.portfolioSummary()

        case "run_js":
            let input = parseJSON(tool.inputJSON) as? [String: Any] ?? [:]
            let code = input["code"] as? String ?? ""
            guard !code.isEmpty else { return "No code provided." }
            do {
                return try await bridge.evaluate(code)
            } catch {
                return "JS error: \(error.localizedDescription)"
            }

        default:
            return "Unknown tool: \(tool.name)"
        }
    }

    private func parseJSON(_ str: String) -> Any? {
        guard let data = str.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
