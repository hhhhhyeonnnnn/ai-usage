import SwiftUI

struct ProviderCard: View {
    let provider: ProviderType
    let state: ProviderState
    let isRefreshing: Bool
    let canRetry: Bool
    let display: UsageDisplay
    let now: Date
    let retry: () -> Void
    var showsTitle = true
    var detailExpanded = false
    var toggleDetails: (() -> Void)? = nil

    var body: some View {
        if showsTitle {
            HStack(alignment: .center, spacing: 8) {
                identity.frame(width: 104, alignment: .leading)
                Spacer(minLength: 0)
                usageContent
            }
            .frame(minHeight: 78)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                usageContent
                if let toggleDetails { detailButton(action: toggleDetails) }
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(provider.displayName).font(.system(size: 12, weight: .semibold))
                if isRefreshing && state.snapshot != nil {
                    ProgressView().controlSize(.mini).accessibilityLabel("Refreshing \(provider.displayName)")
                }
            }
            if let snapshot = state.snapshot {
                Text(snapshot.isStale(relativeTo: now) ? "Local · stale" : snapshot.source.label)
                    .font(.system(size: 9))
                    .foregroundStyle(snapshot.isStale(relativeTo: now) ? Color.orange : Color.secondary)
                if snapshot.source == .localSession {
                    Text(UsageFormatting.updated(snapshot.updatedAt, relativeTo: now, label: "Recorded"))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help("Quota recorded at \(snapshot.updatedAt.formatted()). Refresh rereads local logs.")
                }
            }
            if state.snapshot != nil, let toggleDetails { detailButton(action: toggleDetails) }
        }
    }

    @ViewBuilder
    private var usageContent: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
        case .loaded(let snapshot):
            if snapshot.source == .claudeDesktop && snapshot.buckets.allSatisfy({ $0.resolvedRemainingFraction == nil }) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("한도 정보 없음").font(.system(size: 11, weight: .medium))
                    Text("현재 계정에서 비율을 제공하지 않음")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .trailing)
            } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(snapshot.buckets) { bucket in
                    UsageRing(progress: display.fraction(for: bucket), label: bucket.name,
                              resetText: UsageFormatting.reset(bucket.resetsAt, relativeTo: now),
                              display: display, usedFraction: bucket.resolvedUsedFraction,
                              diameter: showsTitle ? 40 : 52, compact: showsTitle)
                        .frame(width: showsTitle ? 76 : nil)
                }
            }
            }
        case .unavailable:
            failure(provider == .codex ? "No local quota record. Use Codex, then retry." : "Unavailable")
        case .error(let message):
            failure(message)
        }
    }

    private func detailButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: detailExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text("Details").font(.system(size: 10, weight: .medium))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(detailExpanded ? "Collapse quota details" : "Expand quota details")
        .accessibilityValue(detailExpanded ? "Expanded" : "Collapsed")
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry).controlSize(.small).disabled(!canRetry)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .trailing)
    }
}
