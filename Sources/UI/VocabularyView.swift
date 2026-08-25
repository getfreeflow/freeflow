import SwiftUI

struct VocabularyView: View {
    @ObservedObject private var vocabulary = VocabularyStore.shared
    @State private var newTerm = ""
    @State private var query = ""

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Vocabulary",
                subtitle: "Words the transcriber keeps getting wrong."
            ) {
                if vocabulary.terms.count > 6 {
                    SearchField(placeholder: "Search terms", text: $query)
                }
            }

            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Add a term")
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(Theme.foreground)
                    HStack(spacing: Theme.Space.sm) {
                        TextField("e.g. Adithya, Kubernetes, Anthropic", text: $newTerm)
                            .textFieldStyle(ShTextFieldStyle())
                            .onSubmit(add)
                        Button("Add", action: add)
                            .buttonStyle(ShButtonStyle(variant: .primary, size: .md))
                            .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Anything that sounds close to one of these gets corrected to your spelling during cleanup.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }

            let terms = query.isEmpty
                ? vocabulary.terms
                : vocabulary.terms.filter { $0.localizedCaseInsensitiveContains(query) }

            if vocabulary.terms.isEmpty {
                EmptyState(
                    icon: "book.closed",
                    title: "Nothing here yet",
                    message: "Worth adding: your own name, the people you work with, whatever your company calls things, and any acronym you say out loud."
                )
            } else {
                FlowChips(items: terms) { term in
                    vocabulary.remove(term)
                }
            }
        }
    }

    private func add() {
        vocabulary.add(newTerm)
        newTerm = ""
    }
}

/// Wrapping chip layout. Terms are short, so a grid reads better than a list.
struct FlowChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 260), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Text(item)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.mutedForeground)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.muted.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
        }
    }
}
