import AppKit
import SwiftUI

struct ScratchpadView: View {
    @ObservedObject private var store = ScratchpadStore.shared
    @EnvironmentObject private var preferences: Preferences
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PageHeader(
                title: "Scratchpad",
                subtitle: "A page that's always open, for when you just need to get something down."
            ) {
                HStack(spacing: Theme.Space.sm) {
                    Button("Copy all") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.text, forType: .string)
                    }
                    .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
                    .disabled(store.text.isEmpty)

                    Button("Clear") { store.text = "" }
                        .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                        .disabled(store.text.isEmpty)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)

            // The placeholder has to line up with the text view's own insertion
            // point, which sits at the editor's frame origin plus NSTextView's
            // built-in 5pt line-fragment padding. Any extra top padding here and
            // the caret floats above the placeholder text.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .background(Theme.card)
                    .focused($focused)
                    .padding(.horizontal, 22)
                    .padding(.top, 4)

                if store.text.isEmpty {
                    Text("Start typing, or put the cursor here and hold \(preferences.dictationKey.label) to say it out loud.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.leading, 27)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Text("\(store.wordCount) words")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
                Spacer()
                Text("Kept as you type")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .onAppear { focused = true }
    }
}
