import SplitDNSCore
import SwiftUI

struct ResolverEditorView: View {
    @Bindable var draft: ResolverDraft
    let directoryPath: String
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Domain", text: $draft.domain, prompt: Text("corp.example.com"))
                        .disabled(draft.mode == .edit)
                } footer: {
                    FormCaption("Lookups for this domain and all of its subdomains use the name servers below.")
                }

                Section("Name Servers") {
                    ForEach($draft.nameservers) { $field in
                        HStack {
                            TextField("Name server", text: $field.text, prompt: Text("10.0.0.53 or fd00::53"))
                                .labelsHidden()
                            Button("Remove Name Server", systemImage: "minus.circle") {
                                draft.removeNameserver(id: field.id)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(!draft.canRemoveNameserver)
                            .help("Remove this name server")
                        }
                    }
                    Button("Add Name Server", systemImage: "plus.circle", action: draft.addNameserver)
                        .disabled(!draft.canAddNameserver)
                }

                Section {
                    TextField("Port", text: $draft.port, prompt: Text("53 (default)"))
                } header: {
                    Text("Options")
                } footer: {
                    FormCaption("Only needed when the DNS server does not listen on the standard port.")
                }

                Section("File Preview") {
                    if let fileName = draft.targetFileName {
                        Text("\(directoryPath)/\(fileName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(draft.preview.isEmpty ? "The file appears here once you enter a name server." : draft.preview)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(draft.preview.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                message
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid || isSaving)
            }
            .padding(16)
        }
        .frame(width: 500, height: 640)
    }

    @ViewBuilder
    private var message: some View {
        if let error = draft.submissionError {
            Text(error)
                .foregroundStyle(.red)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else if !draft.isPristine, let problem = draft.validationMessage {
            Text(problem)
                .foregroundStyle(.secondary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else if isSaving {
            ProgressView().controlSize(.small)
        } else {
            Text("Saving asks for your administrator password.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}

/// Grouped forms trail-align plain footer text, so the leading alignment is set explicitly.
private struct FormCaption: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
