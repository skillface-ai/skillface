import SwiftUI
import UniformTypeIdentifiers
import YonkaCore

/// Starting an app: paste a skill or a link to one, pick a file, or pick one of the skills
/// Claude Code already has here.
package struct NewAppSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var working = false
    @State private var choosing = false
    @State private var installed: [Skill] = []

    package init(model: AppModel) { self.model = model }

    package var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New App").font(.title2.weight(.semibold))
                Text("Paste a skill, or a link to one.").foregroundStyle(.secondary)
            }
            TextEditor(text: $pasted)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 120)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !installed.isEmpty {
                Text("Or one of yours").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(installed, id: \.name) { skill in
                            Button { create(skill.text) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(skill.name)
                                    Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 170)
            }

            HStack {
                Button("Choose File…") { choosing = true }
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create(pasted) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .disabled(working)
        .task { installed = Skill.installed() }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .text]) { result in
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            create((try? String(contentsOf: url, encoding: .utf8)) ?? "")
        }
    }

    /// Stays open if it couldn't, with why said under the window.
    private func create(_ text: String) {
        working = true
        Task {
            if await model.add(pasted: text) { dismiss() }
            working = false
        }
    }
}
