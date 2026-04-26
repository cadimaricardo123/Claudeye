import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                avatar
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .user {
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    if message.content.isEmpty && message.isStreaming {
                        StreamingDots()
                    } else {
                        renderedText
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                    }

                    if message.isStreaming && !message.content.isEmpty {
                        StreamingDots()
                    }
                }
            }
            .frame(maxWidth: 580, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var avatar: some View {
        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(.green)
    }

    @ViewBuilder
    private var renderedText: some View {
        if let attributed = try? AttributedString(
            markdown: message.content,
            options: .init(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(message.content)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StreamingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(1.0 + 0.4 * sin(phase + Double(i) * .pi * 0.7))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
