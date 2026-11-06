import SplitDNSCore
import SwiftUI

struct ResolverRow: View {
    let entry: ResolverEntry
    let status: ResolverStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.tint)
                .imageScale(.large)
                .help(status.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if entry.isSymlink {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                    .help("Symbolic link, managed elsewhere")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if entry.readError != nil {
            return "Unreadable"
        }
        return entry.nameservers.isEmpty ? "No name servers" : entry.nameservers.joined(separator: ", ")
    }
}
