import SwiftUI

struct ContentView: View {
    @ObservedObject var bridge: TradingViewBridge
    @ObservedObject var coinbase: CoinbaseService
    @ObservedObject var viewModel: ChatViewModel

    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationSplitView {
            TradingPanelView(bridge: bridge, coinbase: coinbase)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            VStack(spacing: 0) {
                messageList
                Divider()
                inputBar
            }
        }
        .navigationTitle("Claudy")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    viewModel.clearHistory()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear conversation")

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel, coinbase: coinbase)
        }
        .onAppear {
            inputFocused = true
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(viewModel.messages) { msg in
                        MessageBubbleView(message: msg)
                            .id(msg.id)
                    }
                    // Scroll anchor
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom")
                }
            }
            // Also scroll when streaming content updates
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                proxy.scrollTo("bottom")
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                // Placeholder
                if viewModel.inputText.isEmpty {
                    Text("Ask about the chart, entry setup, key levels… (↵ to send, ⇧↵ for newline)")
                        .foregroundStyle(Color(NSColor.placeholderTextColor))
                        .font(.body)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $viewModel.inputText)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .frame(minHeight: 36, maxHeight: 140)
                    .focused($inputFocused)
                    .disabled(viewModel.isLoading)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        // Shift+Return → insert newline (default behaviour)
                        guard !press.modifiers.contains(.shift) else { return .ignored }
                        let trimmed = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return .handled }
                        Task { await viewModel.send() }
                        return .handled
                    }
            }

            VStack {
                Spacer(minLength: 0)
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .frame(width: 28, height: 28)
                } else {
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                             ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.textBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
    }
}
