import SwiftUI

struct TradingPanelView: View {
    @ObservedObject var bridge: TradingViewBridge
    @ObservedObject var coinbase: CoinbaseService
    @AppStorage("chromeDebugPort") var port = 9222

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "chart.candlestick.fill")
                    .foregroundStyle(.orange)
                Text("TradingView")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(bridge.isConnected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // TradingView section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(bridge.statusMessage)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !bridge.isConnected {
                            disconnectedView
                        } else {
                            connectedView
                        }
                    }
                    .padding(14)

                    Divider()

                    // Coinbase section
                    coinbaseSectionView
                        .padding(14)

                    Divider()

                    // Primary wallet section
                    coinbasePrimarySection
                        .padding(14)
                }
            }
        }
        .frame(width: 260)
    }

    // MARK: - Coinbase

    private var coinbaseSectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.yellow)
                Text("Coinbase")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(coinbase.isConnected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
            }

            Text(coinbase.statusMessage)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !coinbase.isConnected {
                Button {
                    Task { await coinbase.connect() }
                } label: {
                    Label("Connect", systemImage: "link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.yellow).controlSize(.regular)

                Text("Add API key in Settings (⌘,) first.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Button {
                    Task { await coinbase.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.small)

                if !coinbase.accounts.isEmpty {
                    Divider()
                    ForEach(coinbase.accounts.prefix(12).sorted(by: { $0.totalDouble > $1.totalDouble })) { acc in
                        PanelRow(
                            label: acc.currency,
                            value: fmtCB(acc.availableBalance.value),
                            valueColor: acc.holdDouble > 0 ? .orange : .primary
                        )
                    }
                }

                Button {
                    coinbase.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "link.badge.minus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.small).foregroundStyle(.red)
            }
        }
    }

    private func fmtCB(_ v: String) -> String {
        guard let d = Double(v), d != 0 else { return v }
        return d >= 1 ? String(format: "%.4f", d) : String(format: "%.8f", d)
    }

    // MARK: - Coinbase Primary Wallet

    private var coinbasePrimarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wallet.bifold.fill")
                    .foregroundStyle(.blue)
                Text("Primary Wallet")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(coinbase.isPrimaryConnected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
            }

            Text(coinbase.primaryStatusMessage)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !coinbase.isPrimaryConnected {
                Button {
                    Task { await coinbase.connectPrimary() }
                } label: {
                    Label("Connect", systemImage: "link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.blue).controlSize(.regular)

                Text("Add primary wallet API key in Settings (⌘,) first.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Button {
                    Task { await coinbase.refreshPrimary() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.small)

                if !coinbase.primaryAssets.isEmpty {
                    Divider()

                    // Total
                    HStack {
                        Text("Total")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(coinbase.fmtUSD(coinbase.primaryTotalUSD))
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.blue)
                    }

                    Divider()

                    // Per-asset rows
                    ForEach(coinbase.primaryAssets) { asset in
                        PrimaryAssetRow(asset: asset, coinbase: coinbase)
                        if asset.id != coinbase.primaryAssets.last?.id { Divider().opacity(0.4) }
                    }
                }

                Button {
                    coinbase.disconnectPrimary()
                } label: {
                    Label("Disconnect", systemImage: "link.badge.minus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.small).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Debug port")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("9222", value: $port, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .font(.caption)
            }

            Button {
                Task { await bridge.connect(port: port) }
            } label: {
                Label("Connect", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Divider()

            Button(action: launchChrome) {
                Label("Launch Chrome", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Text("Opens Chrome with TradingView in debug mode on port \(port).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Connected

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await bridge.fetchSnapshot() }
            } label: {
                Label("Refresh data", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if bridge.snapshot.fetchedAt != nil {
                Divider()
                snapshotView
            }

            Divider()

            Button {
                bridge.disconnect()
            } label: {
                Label("Disconnect", systemImage: "link.badge.minus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.red)
        }
    }

    private var snapshotView: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelRow(label: "Symbol",   value: bridge.snapshot.symbol)
            PanelRow(label: "Price",    value: bridge.snapshot.price)

            if bridge.snapshot.change != "—" {
                let changeStr = "\(bridge.snapshot.change) \(bridge.snapshot.changePercent)"
                let isNeg = bridge.snapshot.change.hasPrefix("-")
                PanelRow(label: "Change", value: changeStr,
                         valueColor: isNeg ? .red : .green)
            }

            if bridge.snapshot.interval != "—" {
                PanelRow(label: "Interval", value: bridge.snapshot.interval)
            }
            if bridge.snapshot.volume != "—" {
                PanelRow(label: "Volume",   value: bridge.snapshot.volume)
            }

            if !bridge.snapshot.indicators.isEmpty {
                Divider()
                Text("Indicators")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                ForEach(bridge.snapshot.indicators.keys.sorted(), id: \.self) { key in
                    PanelRow(label: key, value: bridge.snapshot.indicators[key] ?? "—")
                }
            }

            if let date = bridge.snapshot.fetchedAt {
                Text("Updated \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Launch Chrome

    private func launchChrome() {
        let candidates = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
            "/Applications/Chromium.app/Contents/MacOS/Chromium"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            bridge.statusMessage = "Chrome not found. Install Google Chrome."
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = [
            "--remote-debugging-port=\(port)",
            "--user-data-dir=/tmp/chrome-tradingview-\(port)",
            "https://www.tradingview.com/chart/"
        ]
        try? proc.run()

        Task {
            try? await Task.sleep(for: .seconds(3))
            await bridge.connect(port: port)
        }
    }
}

struct PanelRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shows one primary wallet asset: symbol, quantity, current USD value
struct PrimaryAssetRow: View {
    let asset: CBPrimaryAsset
    let coinbase: CoinbaseService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.code)
                    .font(.caption).fontWeight(.semibold)
                Text(coinbase.fmtQty(asset.quantity))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(coinbase.fmtUSD(asset.currentUSD))
                .font(.caption).fontWeight(.medium)
        }
        .padding(.vertical, 2)
    }
}
