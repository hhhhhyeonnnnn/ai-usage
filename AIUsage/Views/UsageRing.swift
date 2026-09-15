import SwiftUI

struct UsageRing: View {
    let progress: Double?
    let label: String
    let resetText: String?
    var display: UsageDisplay = .remaining
    var usedFraction: Double? = nil
    var diameter: CGFloat = 58
    var compact = false

    private var lineWidth: CGFloat { compact ? 4 : 5 }

    private var value: Double? { UsageBucket.normalized(progress) }
    private var tint: Color {
        guard let used = UsageBucket.normalized(usedFraction) else { return .accentColor }
        if used >= 0.95 { return .red }
        if used >= 0.8 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(spacing: compact ? 3 : 6) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: lineWidth)
                if let value, value > 0 {
                    Circle()
                        .trim(from: 0, to: value)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(UsageFormatting.percentage(value))
                    .font(.system(size: compact ? 12 : 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: diameter, height: diameter)
            .padding(compact ? 2 : 3)
            Text(compact ? label.replacingOccurrences(of: " Pool", with: "").replacingOccurrences(of: " / ", with: "/") : label)
                .font(.system(size: compact ? 10 : 12, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 1 : nil)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            if let resetText {
                Text(resetText)
                    .font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .help("\(label) · \(UsageFormatting.percentage(value)) \(display.rawValue)\(resetText.map { " · \($0)" } ?? "")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map { "\(UsageFormatting.percentage($0)) \(display.rawValue). \(resetText ?? "")" } ?? "Usage unknown")
    }
}
