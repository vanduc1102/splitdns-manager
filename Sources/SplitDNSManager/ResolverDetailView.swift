import SplitDNSCore
import SwiftUI

struct ResolverDetailView: View {
    let entry: ResolverEntry
    let status: ResolverStatus
    let onReveal: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Domain") {
                    Text(entry.effectiveDomain)
                        .textSelection(.enabled)
                }
                LabeledContent("Applies to") {
                    Text("\(entry.effectiveDomain) and all of its subdomains")
                }
                LabeledContent("Status") {
                    Label(status.title, systemImage: status.symbolName)
                        .foregroundStyle(status.tint)
                }
                if let explanation = status.explanation {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Name Servers") {
                if entry.nameservers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(entry.nameservers, id: \.self) { nameserver in
                    Text(nameserver)
                        .monospaced()
                        .textSelection(.enabled)
                }
                if let port = entry.port {
                    LabeledContent("Port") {
                        Text(String(port)).monospacedDigit()
                    }
                }
            }

            Section("File") {
                LabeledContent("Path") {
                    HStack {
                        Text(entry.path)
                            .textSelection(.enabled)
                        Button("Reveal in Finder", systemImage: "folder", action: onReveal)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                    }
                }
                if let reason = entry.editBlockReason {
                    Label(reason, systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(entry.rawText.isEmpty ? "(empty file)" : entry.rawText)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(entry.rawText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.fileName)
    }
}
