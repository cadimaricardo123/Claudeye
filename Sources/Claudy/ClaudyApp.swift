import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
class AppState: ObservableObject {
    let bridge   = TradingViewBridge()
    let coinbase = CoinbaseService()
    let viewModel: ChatViewModel

    init() {
        let anthropicKey     = UserDefaults.standard.string(forKey: "anthropicApiKey")    ?? ""
        let cbKeyName        = UserDefaults.standard.string(forKey: "coinbaseApiKeyName") ?? ""
        let cbPrivateKey     = UserDefaults.standard.string(forKey: "coinbasePrivateKey") ?? ""
        let cbPrimaryKeyName = UserDefaults.standard.string(forKey: "cbPrimaryApiKeyName") ?? ""
        let cbPrimaryPEM     = UserDefaults.standard.string(forKey: "cbPrimaryPrivateKey") ?? ""

        viewModel = ChatViewModel(bridge: bridge, coinbase: coinbase, apiKey: anthropicKey)
        coinbase.apiKeyName          = cbKeyName
        coinbase.privateKeyPEM       = cbPrivateKey
        coinbase.primaryApiKeyName   = cbPrimaryKeyName
        coinbase.primaryPrivateKeyPEM = cbPrimaryPEM
    }
}

@main
struct ClaudyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @AppStorage("anthropicApiKey") private var apiKey = ""

    var body: some Scene {
        WindowGroup {
            ContentView(bridge: appState.bridge, coinbase: appState.coinbase, viewModel: appState.viewModel)
                .frame(minWidth: 860, minHeight: 520)
                .onChange(of: apiKey) { _, newKey in
                    appState.viewModel.updateApiKey(newKey)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Clear Conversation") { appState.viewModel.clearHistory() }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        Settings {
            SettingsView(viewModel: appState.viewModel, coinbase: appState.coinbase)
        }
    }
}
