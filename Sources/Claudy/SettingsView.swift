import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropicApiKey")       var apiKey            = ""
    @AppStorage("coinbaseApiKeyName")    var cbKeyName         = ""
    @AppStorage("coinbasePrivateKey")    var cbPrivateKey      = ""
    @AppStorage("cbPrimaryApiKeyName")   var cbPrimaryKeyName  = ""
    @AppStorage("cbPrimaryPrivateKey")   var cbPrimaryPEM      = ""
    @AppStorage("chromeDebugPort")       var port              = 9222

    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var coinbase: CoinbaseService
    @Environment(\.dismiss) var dismiss

    @State private var showKey          = false
    @State private var showPEM          = false
    @State private var showPrimaryPEM   = false
    @State private var testStatus:         TestStatus = .idle
    @State private var cbTestStatus:       TestStatus = .idle
    @State private var cbPrimaryTestStatus: TestStatus = .idle

    enum TestStatus {
        case idle, testing, ok, failed(String)
        var color: Color {
            switch self { case .ok: return .green; case .failed: return .red; default: return .secondary }
        }
        var icon: String {
            switch self { case .ok: return "checkmark.circle.fill"; case .failed: return "xmark.circle.fill";
            case .testing: return "arrow.triangle.2.circlepath"; default: return "key" }
        }
    }

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var keyLooksValid: Bool { trimmedKey.hasPrefix("sk-ant-") && trimmedKey.count > 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section {
                    // Key input row
                    HStack(spacing: 6) {
                        Group {
                            if showKey {
                                TextField("sk-ant-api03-…", text: $apiKey)
                            } else {
                                SecureField("sk-ant-api03-…", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: apiKey) { _, _ in testStatus = .idle }

                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Status row
                    HStack(spacing: 6) {
                        if case .testing = testStatus {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: testStatus.icon)
                                .foregroundStyle(testStatus.color)
                                .frame(width: 14)
                        }

                        switch testStatus {
                        case .idle:
                            if trimmedKey.isEmpty {
                                Text("No key entered.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if keyLooksValid {
                                Text("Key format looks correct.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Key should start with sk-ant- — double-check it.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        case .testing:
                            Text("Testing…").font(.caption).foregroundStyle(.secondary)
                        case .ok:
                            Text("API key works ✓").font(.caption).foregroundStyle(.green)
                        case .failed(let msg):
                            Text(msg).font(.caption).foregroundStyle(.red)
                        }

                        Spacer()

                        Button("Test") { Task { await testKey() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(trimmedKey.isEmpty || testStatus == .testing)
                    }

                    Link("Get a key at console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
                } header: {
                    Text("Anthropic API Key")
                }

                Section {
                    // Key Name  (organizations/.../apiKeys/...)
                    TextField("organizations/…/apiKeys/…", text: $cbKeyName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))

                    // Private Key PEM  (multi-line)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Private Key")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { showPEM.toggle() } label: {
                                Label(showPEM ? "Hide" : "Show",
                                      systemImage: showPEM ? "eye.slash" : "eye")
                                    .font(.caption)
                            }.buttonStyle(.plain)
                        }

                        if showPEM {
                            TextEditor(text: $cbPrivateKey)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 90)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        } else {
                            // Masked preview
                            let preview = cbPrivateKey.isEmpty
                                ? "-----BEGIN EC PRIVATE KEY-----"
                                : "-----BEGIN … (key saved)"
                            Text(preview)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(cbPrivateKey.isEmpty ? .tertiary : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        }
                    }

                    // Status row + test button
                    HStack(spacing: 6) {
                        switch cbTestStatus {
                        case .testing:
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        default:
                            Image(systemName: cbTestStatus.icon)
                                .foregroundStyle(cbTestStatus.color).frame(width: 14)
                        }
                        Group {
                            switch cbTestStatus {
                            case .idle:          Text("Paste key name + PEM private key above")
                            case .testing:       Text("Testing…")
                            case .ok:            Text("Connected ✓")
                            case .failed(let m): Text(m)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(cbTestStatus == .ok ? .green :
                                         cbTestStatus == .idle ? .secondary : .red)
                        Spacer()
                        Button("Test") { Task { await testCoinbase() } }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(cbKeyName.isEmpty || cbPrivateKey.isEmpty || cbTestStatus == .testing)
                    }

                    Link("Get keys at portal.cdp.coinbase.com",
                         destination: URL(string: "https://portal.cdp.coinbase.com")!)
                    .font(.caption)
                } header: {
                    Text("Coinbase Perpetual (Advanced Trade)")
                }

                // ── Primary wallet ──────────────────────────────────────
                Section {
                    // Key Name
                    TextField("organizations/…/apiKeys/…", text: $cbPrimaryKeyName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))

                    // Private Key PEM
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Private Key")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { showPrimaryPEM.toggle() } label: {
                                Label(showPrimaryPEM ? "Hide" : "Show",
                                      systemImage: showPrimaryPEM ? "eye.slash" : "eye")
                                    .font(.caption)
                            }.buttonStyle(.plain)
                        }

                        if showPrimaryPEM {
                            TextEditor(text: $cbPrimaryPEM)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 90)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        } else {
                            let preview = cbPrimaryPEM.isEmpty
                                ? "-----BEGIN EC PRIVATE KEY-----"
                                : "-----BEGIN … (key saved)"
                            Text(preview)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(cbPrimaryPEM.isEmpty ? .tertiary : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color(NSColor.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        }
                    }

                    // Status + test
                    HStack(spacing: 6) {
                        switch cbPrimaryTestStatus {
                        case .testing:
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        default:
                            Image(systemName: cbPrimaryTestStatus.icon)
                                .foregroundStyle(cbPrimaryTestStatus.color).frame(width: 14)
                        }
                        Group {
                            switch cbPrimaryTestStatus {
                            case .idle:          Text("Paste key name + PEM private key above")
                            case .testing:       Text("Testing…")
                            case .ok:            Text("Connected ✓")
                            case .failed(let m): Text(m)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(cbPrimaryTestStatus == .ok ? .green :
                                         cbPrimaryTestStatus == .idle ? .secondary : .red)
                        Spacer()
                        Button("Test") { Task { await testPrimaryCoinbase() } }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(cbPrimaryKeyName.isEmpty || cbPrimaryPEM.isEmpty || cbPrimaryTestStatus == .testing)
                    }

                    Link("Get keys at portal.cdp.coinbase.com",
                         destination: URL(string: "https://portal.cdp.coinbase.com")!)
                    .font(.caption)
                } header: {
                    Text("Coinbase Primary Wallet")
                }

                Section {
                    HStack {
                        Text("Chrome remote debug port")
                        Spacer()
                        TextField("9222", value: $port, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                    Text("Launch Chrome with --remote-debugging-port=\(port)")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("TradingView Connection")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Save & Close") {
                    viewModel.updateApiKey(apiKey)
                    coinbase.apiKeyName        = cbKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    coinbase.privateKeyPEM     = cbPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    coinbase.primaryApiKeyName  = cbPrimaryKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    coinbase.primaryPrivateKeyPEM = cbPrimaryPEM.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 480, height: 700)
    }

    // MARK: - Test

    private func testKey() async {
        testStatus = .testing
        viewModel.updateApiKey(apiKey)

        let key = trimmedKey
        guard !key.isEmpty else { testStatus = .failed("Enter a key first."); return }

        do {
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": "claude-opus-4-7",
                "max_tokens": 10,
                "messages": [["role": "user", "content": "hi"]]
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    testStatus = .ok
                } else {
                    // Read Anthropic's actual error message from the body
                    let apiMsg = extractAPIError(from: data)
                        ?? "HTTP \(http.statusCode)"
                    testStatus = .failed(apiMsg)
                }
            }
        } catch {
            testStatus = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Coinbase test

extension SettingsView {
    func testCoinbase() async {
        cbTestStatus = .testing
        coinbase.apiKeyName    = cbKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
        coinbase.privateKeyPEM = cbPrivateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await coinbase.signedGET("/api/v3/brokerage/accounts?limit=1")
            cbTestStatus = .ok
        } catch {
            cbTestStatus = .failed(error.localizedDescription)
        }
    }

    func testPrimaryCoinbase() async {
        cbPrimaryTestStatus = .testing
        coinbase.primaryApiKeyName   = cbPrimaryKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
        coinbase.primaryPrivateKeyPEM = cbPrimaryPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await coinbase.signedPrimaryGET("/v2/accounts?limit=1")
            cbPrimaryTestStatus = .ok
        } catch {
            cbPrimaryTestStatus = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Helpers

private func extractAPIError(from data: Data) -> String? {
    // Anthropic error body: {"type":"error","error":{"type":"...","message":"..."}}
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let err  = json["error"] as? [String: Any],
          let msg  = err["message"] as? String
    else { return String(data: data, encoding: .utf8) }
    return msg
}

extension SettingsView.TestStatus: Equatable {
    static func == (lhs: SettingsView.TestStatus, rhs: SettingsView.TestStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.testing, .testing), (.ok, .ok): return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}
