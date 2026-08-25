import SwiftUI

/// Circular determinate progress. Used while a speech model downloads, where a
/// spinner would tell you nothing about a 1.5 GB transfer.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 30
    var lineWidth: CGFloat = 3
    var showsPercent = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.border, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(Theme.foreground, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)

            if showsPercent, size >= 28 {
                Text("\(Int(fraction * 100))")
                    .font(.system(size: size * 0.3, weight: .medium))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The engine-status block in the sidebar. Collapsed it's a single line; click it and
/// it opens up with the download detail, model name and what's happening.
struct ModelStatusCard: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    indicator

                    VStack(alignment: .leading, spacing: 1) {
                        Text(headline)
                            .font(Theme.Typography.captionMedium)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        if let progress = controller.modelProgress, progress.stage == .downloading {
                            Text(shortDetail(progress))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.mutedForeground)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().overlay(Theme.border)

                    detailRow("Model", preferences.modelChoice.title)
                    detailRow("Size", preferences.modelChoice.size)

                    if let progress = controller.modelProgress {
                        detailRow("Stage", stageLabel(progress.stage))
                        if progress.stage == .downloading {
                            detailRow("Progress", "\(Int(progress.fraction * 100))%")
                            if !progress.detail.isEmpty {
                                detailRow("Transferred", progress.detail)
                            }
                        }
                    } else if controller.modelReady {
                        detailRow("Stage", "Loaded and warmed")
                        detailRow("Runs on", "This Mac, audio stays local")
                    }

                    detailRow("Trigger", preferences.dictationKey.label)

                    if let error = controller.modelError {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    if !controller.modelReady && controller.modelProgress == nil {
                        Button(controller.modelError == nil ? "Load model" : "Try again") {
                            Task { await controller.reloadModel() }
                        }
                        .buttonStyle(ShButtonStyle(variant: .secondary, size: .sm, fullWidth: true))
                        .padding(.top, 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private var indicator: some View {
        if let progress = controller.modelProgress, progress.stage == .downloading {
            ProgressRing(fraction: progress.fraction, size: 22, lineWidth: 2.5, showsPercent: false)
        } else if controller.modelProgress != nil {
            ProgressView().controlSize(.small).frame(width: 22, height: 22)
        } else if controller.modelError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.destructive)
                .frame(width: 22, height: 22)
        } else {
            Circle()
                .fill(controller.modelReady ? Theme.success : Theme.warning)
                .frame(width: 7, height: 7)
                .frame(width: 22, height: 22)
        }
    }

    private var headline: String {
        if let progress = controller.modelProgress {
            switch progress.stage {
            case .downloading: return "Downloading model"
            case .loading:     return "Loading model"
            case .warming:     return "Almost ready"
            }
        }
        if controller.modelError != nil { return "Couldn't load model" }
        return controller.modelReady ? "Ready" : "Model not loaded"
    }

    private func shortDetail(_ progress: ModelLoadProgress) -> String {
        progress.detail.isEmpty
            ? "\(Int(progress.fraction * 100))% complete"
            : progress.detail
    }

    private func stageLabel(_ stage: ModelLoadProgress.Stage) -> String {
        switch stage {
        case .downloading: return "Downloading"
        case .loading:     return "Loading into memory"
        case .warming:     return "Warming up"
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
