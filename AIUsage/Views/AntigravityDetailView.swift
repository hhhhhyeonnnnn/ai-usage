import SwiftUI

struct AntigravityDetailView: View {
    let snapshot: UsageSnapshot
    @AppStorage("usageDisplay") private var display = UsageDisplay.remaining

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.source == .demo
                 ? "Demo model activity. Child values do not add up to pool usage."
                 : "Shared pools · weekly and 5-hour limits")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            ForEach(snapshot.buckets.filter { !$0.children.isEmpty }) { pool in
                VStack(alignment: .leading, spacing: 7) {
                    Text(pool.name.replacingOccurrences(of: " · 7d", with: "").uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    ForEach(pool.children) { bucket in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bucket.name)
                                if snapshot.source != .demo {
                                    Text(UsageFormatting.reset(bucket.resetsAt, relativeTo: .now))
                                        .font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(UsageFormatting.percentage(display.fraction(for: bucket))) \(display == .remaining ? "left" : "used")")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}
