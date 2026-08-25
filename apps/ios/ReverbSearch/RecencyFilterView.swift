import SwiftUI

/// Histogram of when the loaded listings went live, with a draggable window over
/// it. Port of `recency-filter.tsx`: bars are 3-month buckets, the window is a
/// [newest, oldest] pair in months ago, and the last bucket is open-ended.
///
/// The chart describes the loaded sample only — Reverb has no date-range param,
/// so this is a client-side cut like the title terms.
struct RecencyFilterView: View {
    /// Everything loaded, before any client-side cut: the axis must not jump as
    /// terms are typed.
    let listings: [Listing]
    @Binding var filters: ListingFilters

    /// The window at the moment a drag began — a drag moves relative to it.
    @State private var dragOrigin: (newest: Int, oldest: Int)?

    private var counts: [Int] { Recency.buckets(listings) }
    private var span: Int { Recency.span(bucketCount: counts.count) }

    /// The stored bounds clamped to the current span, which grows as older pages
    /// are appended.
    private var window: (newest: Int, oldest: Int) {
        let oldest = min(filters.oldestMonths ?? span, span)
        return (min(filters.newestMonths, oldest - Recency.bucketMonths), oldest)
    }

    var body: some View {
        let counts = counts
        let (newest, oldest) = window

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Listed date range").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(summary(newest: newest, oldest: oldest))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            bars(counts, newest: newest, oldest: oldest)

            // Buckets are equal width, so only the ends need labelling to stay
            // legible when the chart is narrow.
            HStack {
                Text("now")
                Spacer()
                Text("\(span)+ mo ago").monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            slider(newest: newest, oldest: oldest)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func summary(newest: Int, oldest: Int) -> String {
        let from = newest == 0 ? "now" : "\(newest) mo ago"
        let to = oldest >= span ? "oldest" : "\(oldest) mo ago"
        return "\(from) – \(to)"
    }

    private func bars(_ counts: [Int], newest: Int, oldest: Int) -> some View {
        let peak = max(counts.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(counts.indices, id: \.self) { i in
                let start = i * Recency.bucketMonths
                let included = start >= newest && start < oldest
                RoundedRectangle(cornerRadius: 2)
                    .fill(included ? Color.accentColor : Color.secondary)
                    .opacity(included ? 1 : 0.4)
                    // A hair of height on empty buckets keeps the axis readable.
                    .frame(height: max(CGFloat(counts[i]) / CGFloat(peak) * 64, 2))
            }
        }
        .frame(height: 64, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// One track with two thumbs and a draggable band between them — a window
    /// that moves as a unit, which no stock slider expresses.
    private func slider(newest: Int, oldest: Int) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (months: Int) in CGFloat(months) / CGFloat(span) * width }

            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 6)

                Capsule()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: max(x(oldest) - x(newest), 1), height: 6)
                    .offset(x: x(newest))
                    .gesture(drag(width: width) { start, delta in
                        // The band keeps its width; the span ends stop it rather
                        // than squashing it.
                        let w = start.oldest - start.newest
                        let from = clampMonths(start.newest + delta, 0, span - w)
                        return (from, from + w)
                    })

                thumb(label: "Newest bound", value: newest, at: x(newest))
                    .gesture(drag(width: width) { start, delta in
                        (clampMonths(start.newest + delta, 0, start.oldest - Recency.bucketMonths),
                         start.oldest)
                    })
                    .accessibilityAdjustableAction { nudge($0, edge: .newest) }

                thumb(label: "Oldest bound", value: oldest, at: x(oldest))
                    .gesture(drag(width: width) { start, delta in
                        (start.newest,
                         clampMonths(start.oldest + delta, start.newest + Recency.bucketMonths, span))
                    })
                    .accessibilityAdjustableAction { nudge($0, edge: .oldest) }
            }
            .frame(height: 28)
        }
        .frame(height: 28)
    }

    private func thumb(label: String, value: Int, at x: CGFloat) -> some View {
        Circle()
            .fill(Color(.systemBackground))
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: 22, height: 22)
            // Centre the thumb on its value rather than hanging it off the left.
            .offset(x: x - 11)
            .accessibilityLabel(label)
            .accessibilityValue("\(value) months ago")
    }

    private enum Edge { case newest, oldest }

    /// VoiceOver's increment/decrement, one bucket at a time.
    private func nudge(_ direction: AccessibilityAdjustmentDirection, edge: Edge) {
        let step = direction == .increment ? Recency.bucketMonths : -Recency.bucketMonths
        let (newest, oldest) = window
        switch edge {
        case .newest:
            apply((clampMonths(newest + step, 0, oldest - Recency.bucketMonths), oldest))
        case .oldest:
            apply((newest, clampMonths(oldest + step, newest + Recency.bucketMonths, span)))
        }
    }

    /// Shared drag plumbing: snap the travelled distance to whole buckets, hand
    /// it to the caller's edge/band math, and store the result.
    private func drag(
        width: CGFloat,
        _ move: @escaping ((newest: Int, oldest: Int), Int) -> (Int, Int)
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragOrigin ?? window
                dragOrigin = start
                let raw = value.translation.width / max(width, 1) * CGFloat(span)
                let delta = Int((raw / CGFloat(Recency.bucketMonths)).rounded()) * Recency.bucketMonths
                apply(move(start, delta))
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func apply(_ range: (Int, Int)) {
        filters.newestMonths = range.0
        // The oldest end stays open when it sits at the span, so appended pages
        // extend the window instead of being filtered out on arrival.
        filters.oldestMonths = range.1 >= span ? nil : range.1
    }

    private func clampMonths(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(v, lo), max(lo, hi))
    }
}
