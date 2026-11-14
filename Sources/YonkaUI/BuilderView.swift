import SwiftUI
import YonkaCore

/// An app being built, or changed: the conversation with the builder on the left, and the
/// interface as it stands on the right, drawn on its sample data.
struct BuilderView: View {
    let model: AppModel
    let app: SkillApp

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Steps(stage: app.info.stage)
                Divider()
                if let session = model.buildSession {
                    ChatView(
                        messages: model.messages(of: session), busy: model.live[session.id] != nil,
                        status: model.live[session.id]?.status ?? "",
                        send: { model.send($0, in: session.id) }, stop: { model.stop(session.id) })
                }
            }
            .frame(width: 380)
            Divider()
            InterfaceView(html: model.interface, state: model.preview, failed: model.interfaceFailed)
                .id(model.interface)
                .overlay(alignment: .topTrailing) {
                    Text("Preview").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .padding(12)
                }
        }
    }
}

/// Where the build is: the four steps, the current one marked.
private struct Steps: View {
    let stage: SkillApp.Stage

    var body: some View {
        let steps = SkillApp.Stage.allCases.filter { $0 != .done }
        let current = steps.firstIndex(of: stage) ?? steps.count
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Text(step.rawValue.capitalized)
                    .font(.caption.weight(index == current ? .semibold : .regular))
                    .foregroundStyle(index == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: stage)
    }
}

/// A conversation, drawn natively: the builder's. An app's own conversations are its interface's.
struct ChatView: View {
    let messages: [Session.Message]
    let busy: Bool
    let status: String
    let send: (String) -> Void
    let stop: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    /// What the last question offers, until it's answered.
    private var choices: [String] {
        guard !busy, let last = messages.last, last.role == .assistant else { return [] }
        return Choices.split(last.text).choices
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            MessageRow(message: message)
                        }
                        if busy {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(status.isEmpty ? "Thinking" : status).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .onChange(of: messages) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: busy) { proxy.scrollTo("end", anchor: .bottom) }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    Button { send(choice) } label: {
                        Text(choice).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(choices.isEmpty ? "Message" : "Or say something else", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(1...6).focused($focused)
                        .onSubmit(submit)
                    if busy {
                        Button("Stop", systemImage: "stop.circle.fill", action: stop)
                            .labelStyle(.iconOnly).buttonStyle(.plain).font(.title2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.separator, lineWidth: 1) }
                .padding(.horizontal, 1)
            }
            .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 4)
        }
        .onAppear { focused = true }
    }

    private func submit() {
        guard !busy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        send(draft)
        draft = ""
    }
}

private struct MessageRow: View {
    let message: Session.Message

    var body: some View {
        if message.role == .user {
            Text(message.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        } else {
            // Its choices are the buttons under the conversation, not text in it.
            let body = Choices.split(message.text).body
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            Text((try? AttributedString(markdown: body, options: options)) ?? AttributedString(body))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }
}
