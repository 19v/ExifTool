import SwiftUI

struct LocalPhotosStatusContent: View {
    let snapshot: LocalPhotosStatusSnapshot
    let trailingSystemImageName: String?

    init(
        snapshot: LocalPhotosStatusSnapshot,
        trailingSystemImageName: String? = nil
    ) {
        self.snapshot = snapshot
        self.trailingSystemImageName = trailingSystemImageName
    }

    var body: some View {
        HStack(spacing: 12) {
            statusPulse

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let localPhotosCount = snapshot.localPhotosCount {
                        countChip(title: AppLocalization.string("localPhotos.count.local"), value: localPhotosCount)
                    }

                    if showsAlbumCount, let localAlbumsCount = snapshot.localAlbumsCount {
                        countChip(title: AppLocalization.string("localPhotos.count.albums"), value: localAlbumsCount)
                    }
                }

                Text(snapshot.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 8)

            if let trailingSystemImageName {
                Image(systemName: trailingSystemImageName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.bounce.byLayer, value: snapshot.text)
            }
        }
        .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: snapshot.localPhotosCount)
        .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: snapshot.localAlbumsCount)
        .animation(.easeInOut(duration: 0.2), value: snapshot.text)
    }

    private var showsAlbumCount: Bool {
        switch snapshot.state {
        case .buildingAlbums, .complete:
            return true
        case .loading, .paginating, .none:
            return snapshot.localAlbumsCount != nil && snapshot.localAlbumsCount != 0
        }
    }

    private var statusPulse: some View {
        Circle()
            .fill(statusColor.gradient)
            .frame(width: 10, height: 10)
            .overlay {
                Circle()
                    .stroke(statusColor.opacity(0.24), lineWidth: 8)
                    .scaleEffect(needsPulse ? 1.17 : 1)
                    .opacity(needsPulse ? 1 : 0.35)
            }
            .animation(
                needsPulse ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .easeOut(duration: 0.2),
                value: needsPulse
            )
    }

    @ViewBuilder
    private func countChip(title: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatted(value))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch snapshot.state {
        case .complete:
            return .green
        case .loading, .paginating, .buildingAlbums, .none:
            return .orange
        }
    }

    private var needsPulse: Bool {
        switch snapshot.state {
        case .complete:
            return false
        case .loading, .paginating, .buildingAlbums, .none:
            return true
        }
    }

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
