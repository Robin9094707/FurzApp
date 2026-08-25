import SwiftUI
import UIKit

enum RJTheme {
    static let corner: CGFloat = 24
    static let smallCorner: CGFloat = 16
}

extension View {
    @ViewBuilder
    func premiumGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .premiumGlass(in: RoundedRectangle(cornerRadius: RJTheme.corner, style: .continuous))
    }
}

struct RJBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 470
            )
            RadialGradient(
                colors: [Color.orange.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

struct MetricPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .premiumGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}


struct RatingControl: View {
    let title: String
    @Binding var value: Int
    var symbol: String = "star.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)/5")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        value = index
                        Haptics.impact(.light)
                    } label: {
                        Image(systemName: symbol)
                            .font(.title3)
                            .symbolVariant(index <= value ? .fill : .none)
                            .foregroundStyle(index <= value ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(index) von 5")
                }
            }
        }
    }
}


struct WaveformView: View {
    let samples: [CGFloat]
    var progress: Double? = nil
    var height: CGFloat = 78

    var body: some View {
        GeometryReader { proxy in
            let count = max(samples.count, 1)
            let spacing: CGFloat = 2
            let barWidth = max(1.5, (proxy.size.width - CGFloat(count - 1) * spacing) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(barStyle(index: index, count: count))
                        .frame(width: barWidth, height: max(4, height * value))
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Audio-Wellenform")
    }

    private func barStyle(index: Int, count: Int) -> AnyShapeStyle {
        guard let progress else { return AnyShapeStyle(Color.accentColor.gradient) }
        let position = Double(index) / Double(max(count - 1, 1))
        return position <= progress
            ? AnyShapeStyle(Color.accentColor.gradient)
            : AnyShapeStyle(Color.secondary.opacity(0.28))
    }
}


struct FartRow: View {
    let entry: FartEntry
    let folderName: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: entry.loudness.symbol)
                    .font(.title3.bold())
                    .foregroundStyle(.tint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(1)
                    if entry.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                    }
                }
                Text(entry.eventDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label(entry.loudness.rawValue, systemImage: entry.loudness.symbol)
                    if let folderName { Label(folderName, systemImage: "folder") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label("\(entry.personalRating)", systemImage: "star.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.tint)
                if entry.audioFilename != nil {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
