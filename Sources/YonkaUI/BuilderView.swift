import AppKit
import SwiftUI
import YonkaCore

/// An app being built, or changed: the conversation with the builder on the left, and on the
/// right the interface as it stands, on its sample data, floating on the desk. While the user
/// is choosing, the versions the builder drew sit under it as live thumbnails.
struct BuilderView: View {
    @Bindable var model: AppModel
    let app: SkillApp

    private var busy: Bool { model.buildSession.map { model.live[$0.id] != nil } ?? false }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let session = model.buildSession {
                    ChatView(
                        messages: model.messages(of: session), busy: busy,
                        status: model.live[session.id]?.status ?? "",
                        send: { model.send($0, in: session.id) }, stop: { model.stop(session.id) })
                }
            }
            .frame(width: 360)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
            VStack(spacing: 16) {
                HStack {
                    if model.choosing, let design = model.design {
                        Text("\(design.id) · \(design.name)").font(Theme.serif(20))
                        Text(design.idea).foregroundStyle(Theme.dim).lineLimit(1)
                    } else {
                        Text("Preview").font(Theme.serif(20))
                        Text("on sample data").foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    if model.choosing {
                        Button { model.choose() } label: { Text("Take this one").pill(filled: true) }
                            .buttonStyle(.plain).disabled(busy)
                    }
                }
                .font(.callout)
                let html = model.choosing ? model.design?.html ?? model.interface : model.interface
                InterfaceView(html: html, state: model.preview, failed: model.interfaceFailed)
                    .id(html)
                    .stage()
                if model.choosing {
                    HStack(spacing: 16) {
                        ForEach(model.designs) { design in
                            Thumbnail(design: design, state: model.preview, selected: design.id == model.design?.id) {
                                model.designID = design.id
                            }
                        }
                    }
                }
            }
            .padding(.leading, 20)
        }
        .padding([.horizontal, .bottom], 14)
    }
}

/// One version, drawn live and small: the page at full size, scaled down, so what's chosen
/// from is the real thing.
private struct Thumbnail: View {
    let design: Design
    let state: Interface.State
    let selected: Bool
    let pick: () -> Void

    private static let page = CGSize(width: 1040, height: 650)
    private static let scale = 0.16

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 8) {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                InterfaceView(html: design.html, state: state)
                    .frame(width: Self.page.width, height: Self.page.height)
                    .scaleEffect(Self.scale)
                    .frame(width: Self.page.width * Self.scale, height: Self.page.height * Self.scale)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .padding(4)
                    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 2 : 1) }
                Text("\(design.id) · \(design.name)")
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.dim))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(design.idea)
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
