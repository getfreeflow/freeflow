import AppKit
import SwiftUI

struct MeetingsView: View {
    @ObservedObject private var recorder = MeetingRecorder.shared
    @ObservedObject private var meetings = MeetingsStore.shared

    @State private var query = ""
    @State private var selected: Meeting?

    var body: some View {
        if let meeting = selected {
            MeetingDetail(meeting: meeting) { selected = nil }
        } else {
            list
        }
    }

    private var list: some View {
        PageScroll {
            PageHeader(
                title: "Meetings",
                subtitle: "Recorded from your Mac's own audio. Nothing joins your call as a participant."
            ) {
                if !meetings.meetings.isEmpty {
                    SearchField(placeholder: "Search meetings", text: $query)
                }
            }

            recorderCard

            let results = meetings.search(query)
            if meetings.meetings.isEmpty {
                EmptyState(
                    icon: "record.circle",
                    title: "Nothing recorded yet",
                    message: "Hit record before your next call. Both halves of the conversation get captured, transcribed here on your Mac, and written up afterwards."
                )
            } else if results.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "No matches", message: "No meeting matches “\(query)”.")
            } else {
                VStack(spacing: Theme.Space.sm) {
                    ForEach(results) { meeting in
                        MeetingRow(meeting: meeting) { selected = meeting }
                    }
                }
            }
        }
    }

    private var recorderCard: some View {
        ShCard {
            HStack(spacing: Theme.Space.lg) {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Theme.destructive.opacity(0.15) : Theme.muted)
                        .frame(width: 48, height: 48)
                    if recorder.isRecording {
                        LevelMeter(level: recorder.level, barCount: 5)
                    } else if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "record.circle")
                            .font(.system(size: 19))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.foreground)
                    Text(statusDetail)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if recorder.isRecording {
                    Text(recorder.elapsedDescription)
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.foreground)

                    Button("Stop") { Task { await recorder.stop() } }
                        .buttonStyle(ShButtonStyle(variant: .destructive, size: .md))
                } else {
                    Button("Start recording") { Task { await recorder.start() } }
                        .buttonStyle(ShButtonStyle(variant: .primary, size: .md))
                        .disabled(isBusy)
                }
            }
        }
    }

    private var isBusy: Bool {
        recorder.state == .transcribing || recorder.state == .summarizing
    }

    private var statusTitle: String {
        switch recorder.state {
        case .recording:   return "Recording"
        case .transcribing: return "Transcribing"
        case .summarizing:  return "Writing summary"
        case .failed:       return "Couldn't record"
        case .idle:         return "Ready to record"
        }
    }

    private var statusDetail: String {
        switch recorder.state {
        case .recording:
            return "Capturing system audio and your microphone."
        case .transcribing:
            return "Running the audio through Whisper on your Mac. Long meetings take a while."
        case .summarizing:
            return "Pulling out key points, decisions and action items."
        case .failed(let message):
            return message
        case .idle:
            return CredentialStore.shared.hasKey
                ? "Anything that plays through your speakers gets picked up: calls, huddles, a video you're watching."
                : "Transcripts work as-is. Summaries need a Groq key, which you can add in Settings."
        }
    }
}

// MARK: - Row

private struct MeetingRow: View {
    let meeting: Meeting
    let open: () -> Void

    @ObservedObject private var store = MeetingsStore.shared
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Space.lg) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.mutedForeground)

                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title)
                        .font(Theme.Typography.bodyMedium)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    Text("\(meeting.date.formatted(date: .abbreviated, time: .shortened)) · \(meeting.durationDescription) · \(meeting.wordCount) words")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }

                Spacer(minLength: 0)

                if hovering {
                    Button {
                        store.remove(meeting)
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.mutedForeground)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .padding(Theme.Space.md)
            .background(hovering ? Theme.accent : Theme.muted.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Detail

private struct MeetingDetail: View {
    let meeting: Meeting
    let back: () -> Void

    @State private var question = ""
    @State private var answer = ""
    @State private var asking = false
    @State private var showTranscript = false

    var body: some View {
        PageScroll {
            Button {
                back()
            } label: {
                Label("All meetings", systemImage: "chevron.left")
                    .font(Theme.Typography.small)
            }
            .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))

            PageHeader(
                title: meeting.title,
                subtitle: "\(meeting.date.formatted(date: .complete, time: .shortened)) · \(meeting.durationDescription)"
            )

            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Summary")
                        .font(Theme.Typography.heading)
                        .foregroundStyle(Theme.foreground)

                    if meeting.summary.isEmpty {
                        Text("No summary. Add a Groq API key in Settings and future recordings will be summarized automatically.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(meeting.summary)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

            askCard

            ShCard {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack {
                        Text("Transcript")
                            .font(Theme.Typography.heading)
                            .foregroundStyle(Theme.foreground)
                        Spacer()
                        Button(showTranscript ? "Hide" : "Show") { showTranscript.toggle() }
                            .buttonStyle(ShButtonStyle(variant: .ghost, size: .sm))
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(meeting.transcript, forType: .string)
                        }
                        .buttonStyle(ShButtonStyle(variant: .outline, size: .sm))
                    }

                    if showTranscript {
                        Text(meeting.transcript)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var askCard: some View {
        ShCard {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Ask about this meeting")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.foreground)

                HStack(spacing: Theme.Space.sm) {
                    TextField("What did I miss? What were the action items?", text: $question)
                        .textFieldStyle(ShTextFieldStyle())
                        .onSubmit(ask)
                    Button("Ask", action: ask)
                        .buttonStyle(ShButtonStyle(variant: .primary, size: .md))
                        .disabled(asking || question.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if asking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the transcript…")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                } else if !answer.isEmpty {
                    Text(answer)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(Theme.Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.muted.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
            }
        }
    }

    private func ask() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        asking = true
        answer = ""
        Task {
            let result = await MeetingRecorder.shared.ask(prompt, about: meeting)
            await MainActor.run {
                answer = result
                asking = false
            }
        }
    }
}
