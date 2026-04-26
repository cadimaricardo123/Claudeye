import Foundation
import SwiftUI

// Thread-safe CDP WebSocket session via actor
actor CDPChannel {
    nonisolated let socket: URLSessionWebSocketTask
    private var messageId = 0
    private var pending: [Int: CheckedContinuation<String?, Error>] = [:]

    init(socket: URLSessionWebSocketTask) {
        self.socket = socket
    }

    func nextId() -> Int {
        messageId += 1
        return messageId
    }

    func setPending(_ id: Int, _ cont: CheckedContinuation<String?, Error>) {
        pending[id] = cont
    }

    func resolve(id: Int, value: String?) {
        pending.removeValue(forKey: id)?.resume(returning: value)
    }

    func fail(id: Int, error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    func failAll() {
        let err = NSError(domain: "CDPChannel", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Connection lost"])
        pending.values.forEach { $0.resume(throwing: err) }
        pending.removeAll()
    }
}

@MainActor
class TradingViewBridge: ObservableObject {
    @Published var isConnected = false
    @Published var snapshot = ChartSnapshot()
    @Published var statusMessage = "Not connected"

    private var channel: CDPChannel?

    // MARK: - Public API

    func connect(port: Int = 9222) async {
        statusMessage = "Connecting to Chrome on port \(port)…"
        do {
            let listURL = URL(string: "http://localhost:\(port)/json")!
            let (data, _) = try await URLSession.shared.data(from: listURL)
            let targets = try JSONDecoder().decode([CDPTarget].self, from: data)

            let target = targets.first(where: { $0.url.contains("tradingview.com") && $0.webSocketDebuggerUrl != nil })
                      ?? targets.first(where: { $0.type == "page" && $0.webSocketDebuggerUrl != nil })

            guard let target, let wsStr = target.webSocketDebuggerUrl,
                  let wsURL = URL(string: wsStr) else {
                statusMessage = "No TradingView tab found. Open tradingview.com first."
                return
            }

            let ws = URLSession.shared.webSocketTask(with: wsURL)
            ws.resume()

            let ch = CDPChannel(socket: ws)
            channel = ch

            startListening(channel: ch)

            // enable Runtime domain so evaluate works
            try await rawSend(channel: ch, method: "Runtime.enable", params: [:])

            isConnected = true
            statusMessage = "Connected — \(target.title)"

            await refreshSnapshot()

        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        Task { [weak self] in
            await self?.channel?.failAll()
            await self?.channel?.socket.cancel(with: .normalClosure, reason: nil)
        }
        channel = nil
        isConnected = false
        statusMessage = "Disconnected"
    }

    func fetchSnapshot() async -> ChartSnapshot {
        await refreshSnapshot()
        return snapshot
    }

    func evaluate(_ js: String) async throws -> String {
        guard let ch = channel else { throw BridgeError.notConnected }
        let id = await ch.nextId()
        let payload: [String: Any] = [
            "id": id,
            "method": "Runtime.evaluate",
            "params": [
                "expression": js,
                "returnByValue": true,
                "awaitPromise": false
            ]
        ]
        let msgStr = try encodeJSON(payload)

        // 8-second timeout so a dead Chrome connection never hangs the agent
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    Task {
                        await ch.setPending(id, cont)
                        do {
                            try await ch.socket.send(.string(msgStr))
                        } catch {
                            await ch.fail(id: id, error: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                await ch.fail(id: id, error: BridgeError.timeout)
                throw BridgeError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result ?? "null"
        }
    }

    // MARK: - Private

    private func refreshSnapshot() async {
        guard isConnected else { return }
        do {
            let raw = try await evaluate(snapshotJS)
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            var snap = ChartSnapshot()
            // symbol from widget API or DOM, fallback to page title regex
            if let sym = json["symbol"] as? String { snap.symbol = sym }
            else if let title = json["pageTitle"] as? String,
                    let m = title.range(of: #"^([A-Z0-9./]+)"#, options: .regularExpression) {
                snap.symbol = String(title[m])
            }
            snap.price          = json["price"] as? String ?? "—"
            snap.change         = json["change"] as? String ?? "—"
            snap.changePercent  = json["changePercent"] as? String ?? "—"
            snap.interval       = json["interval"] as? String ?? "—"
            snap.volume         = json["volume"] as? String ?? "—"
            if let inds = json["indicators"] as? [String: String] {
                snap.indicators = inds
            }
            snap.fetchedAt = Date()
            snapshot = snap
        } catch {
            // silently ignore snapshot errors
        }
    }

    private func startListening(channel: CDPChannel) {
        Task { [weak self] in
            while true {
                guard self != nil else { break }
                do {
                    let msg = try await channel.socket.receive()
                    if case .string(let str) = msg,
                       let data = str.data(using: .utf8),
                       let resp = try? JSONDecoder().decode(CDPResponse.self, from: data),
                       let id = resp.id {
                        if let err = resp.error {
                            await channel.fail(id: id, error: BridgeError.cdpError(err.message))
                        } else {
                            await channel.resolve(id: id, value: resp.result?.result?.value)
                        }
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.isConnected = false
                        self?.statusMessage = "Connection lost"
                        self?.channel = nil
                    }
                    await channel.failAll()
                    break
                }
            }
        }
    }

    private func rawSend(channel: CDPChannel, method: String, params: [String: Any]) async throws {
        let id = await channel.nextId()
        let payload: [String: Any] = ["id": id, "method": method, "params": params]
        try await channel.socket.send(.string(encodeJSON(payload)))
    }

    private func encodeJSON(_ obj: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Snapshot JS

    private let snapshotJS = #"""
    (() => {
      const s = {};
      s.pageTitle = document.title;

      // Price — try multiple selector patterns TradingView uses
      for (const sel of [
        '.tv-symbol-price-quote__value',
        '[data-field="last_price"]',
        '.js-symbol-last',
        '[class*="lastPrice"]',
        '[class*="priceValue"]'
      ]) {
        const el = document.querySelector(sel);
        if (el && el.textContent.trim()) { s.price = el.textContent.trim(); break; }
      }

      // Symbol from header
      const symEl = document.querySelector(
        '.tv-symbol-header__description, [class*="symbol-header"] [class*="description"]'
      );
      if (symEl) s.symbol = symEl.textContent.trim();

      // Change / change %
      const chEl = document.querySelector('[class*="priceChange"], [class*="change-value"]');
      if (chEl) s.change = chEl.textContent.trim();
      const chPctEl = document.querySelector('[class*="changePercent"], [class*="change-percent"]');
      if (chPctEl) s.changePercent = chPctEl.textContent.trim();

      // Volume
      const volEl = document.querySelector('[data-field="volume"], [class*="volume"] [class*="value"]');
      if (volEl) s.volume = volEl.textContent.trim();

      // TradingView widget API (works on advanced charts page)
      try {
        const wk = Object.keys(window).find(k => {
          try { return typeof window[k]?.activeChart === 'function'; } catch { return false; }
        });
        if (wk) {
          const chart = window[wk].activeChart();
          s.symbol = s.symbol || chart.symbol();
          s.interval = chart.resolution();
        }
      } catch (_) {}

      // Indicator legend values
      const inds = {};
      document.querySelectorAll('[class*="legend-series-item"], [class*="legacyWrap"]').forEach(item => {
        const t = item.querySelector('[class*="title"]')?.textContent?.trim();
        const vs = Array.from(item.querySelectorAll('[class*="value"]'))
                       .map(v => v.textContent.trim()).filter(Boolean);
        if (t && vs.length) inds[t] = vs.join(' | ');
      });
      s.indicators = inds;

      return JSON.stringify(s);
    })()
    """#

    // MARK: - Errors

    enum BridgeError: LocalizedError {
        case notConnected
        case connectionLost
        case timeout
        case cdpError(String)

        var errorDescription: String? {
            switch self {
            case .notConnected:      return "Not connected to Chrome"
            case .connectionLost:    return "Chrome connection was lost"
            case .timeout:           return "TradingView timed out — Chrome may have closed"
            case .cdpError(let m):   return "CDP: \(m)"
            }
        }
    }
}
