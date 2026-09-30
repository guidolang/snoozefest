import SwiftUI

enum Theme {
    static let firstStretch = Color.indigo
    static let laterStretch = Color.indigo.opacity(0.45)
    static let excluded = Color.gray.opacity(0.35)
    static let intervention = Color.red
    static let badNight = Color.orange
    /// Things that need the user: unlogged nights and the "Log last night" button.
    static let attention = Color.orange
    static let average = Color.primary
    static let before = Color.gray
    static let after = Color.indigo
}

/// The app's main-action button look: system prominent glass on iOS 26, filled capsule before.
struct ProminentCapsuleStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }
}

/// A short burst of falling confetti, played each time `trigger` changes.
/// Drawn with Canvas (no images); skipped when Reduce Motion is on.
struct ConfettiView: View {
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var pieces: [Piece] = []

    static let duration = 4.5
    /// Lets the log sheet finish sliding away before the burst starts.
    static let startDelay = 0.35
    private static let colors: [Color] = [.indigo, .purple, .pink, .orange, .yellow, .mint, .cyan]

    private struct Piece {
        var x: Double         // start position, fraction of the width
        var delay: Double     // seconds before it appears
        var fall: Double      // initial downward speed, points per second
        var sway: Double      // side-to-side amplitude, points
        var swaySpeed: Double
        var spin: Double      // radians per second
        var flip: Double      // flutter speed (fakes 3D tumbling)
        var size: CGSize
        var color: Color
        var isCircle: Bool
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let age = t - piece.delay
                    guard age > 0 else { continue }
                    let y = -20 + piece.fall * age + 70 * age * age
                    guard y < size.height + 20 else { continue }
                    let x = piece.x * size.width + sin(age * piece.swaySpeed) * piece.sway
                    let fade = min(1, max(0, (Self.duration - t) / 0.8))
                    var ctx = context
                    ctx.opacity = fade
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(piece.spin * age))
                    ctx.scaleBy(x: cos(age * piece.flip), y: 1)
                    let rect = CGRect(origin: CGPoint(x: -piece.size.width / 2, y: -piece.size.height / 2), size: piece.size)
                    ctx.fill(piece.isCircle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5),
                             with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard !reduceMotion else { return }
            pieces = (0..<120).map { _ in
                let w = Double.random(in: 6...11)
                return Piece(x: .random(in: 0...1), delay: Self.startDelay + .random(in: 0...0.8), fall: .random(in: 40...180),
                             sway: .random(in: 8...30), swaySpeed: .random(in: 2...5), spin: .random(in: -6...6),
                             flip: .random(in: 3...9), size: CGSize(width: w, height: w * .random(in: 0.4...1.6)),
                             color: Self.colors.randomElement()!, isCircle: Double.random(in: 0...1) < 0.2)
            }
            let started = Date.now
            start = started
            Task {
                try? await Task.sleep(for: .seconds(Self.duration))
                if start == started { start = nil }
            }
        }
    }
}

extension Evidence {
    var color: Color {
        switch self {
        case .strong: .green
        case .suggestive: .orange
        case .none, .insufficient: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .strong: "checkmark.seal.fill"
        case .suggestive: "eye.fill"
        case .none: "equal.circle"
        case .insufficient: "hourglass"
        }
    }
}

struct EvidenceBadge: View {
    var evidence: Evidence
    var compact = false

    var body: some View {
        Label(compact ? evidence.shortLabel : evidence.label, systemImage: evidence.symbol)
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(evidence.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(evidence.color.opacity(0.12), in: Capsule())
    }
}

/// A small horizontal bar showing sleep stretches, scaled to 12 hours.
struct NightBar: View {
    var segments: [Double]
    var excluded = false
    var scale = 12.0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, hours in
                    Capsule()
                        .fill(excluded ? Theme.excluded : (index == 0 ? Theme.firstStretch : Theme.laterStretch))
                        .frame(width: max(3, geo.size.width * min(hours, scale) / scale - 2))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

extension Double {
    /// "+0.5 h" / "−1.25 h"
    var signedHoursText: String {
        let sign = self > 0.005 ? "+" : (self < -0.005 ? "−" : "±")
        return "\(sign)\(abs(self).formatted(.number.precision(.fractionLength(0...2)))) h"
    }

    /// 0.64 → "64%"
    var percentText: String {
        isNaN ? "–" : formatted(.percent.precision(.fractionLength(0)))
    }

    /// Difference in percentage points: 0.21 → "+21 pts"
    var signedPointsText: String {
        guard !isNaN else { return "–" }
        let points = Int((self * 100).rounded())
        return points > 0 ? "+\(points) pts" : (points < 0 ? "−\(-points) pts" : "±0 pts")
    }

    var pValueText: String {
        self < 0.001 ? "< 0.001" : formatted(.number.precision(.fractionLength(3)))
    }
}
