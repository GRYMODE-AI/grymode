import SwiftUI

/// The look as one styled outfit: the AI-rendered image of all pieces worn together when it's
/// ready, otherwise the look's own garment photos arranged as a collage.
struct LookVisualView: View {
    let look: OutfitLook
    var showsStatus = true

    var body: some View {
        ZStack {
            GMColor.surfaceSunken
            if let url = look.styledImageURL {
                GMRemoteImage(url: url, contentMode: .fill)
                    .transition(.opacity)
            } else {
                GarmentCollage(garments: look.orderedGarments)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: look.styledImageURL != nil)
        .overlay(alignment: .bottomLeading) {
            if showsStatus, look.isStyling {
                HStack(spacing: GMSpacing.xxs) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(GMColor.textPrimary)
                    Text("Styling…")
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textPrimary)
                }
                .padding(.horizontal, GMSpacing.xs)
                .padding(.vertical, GMSpacing.xxs)
                .background(GMColor.surface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: GMRadius.sm, style: .continuous))
                .padding(GMSpacing.xs)
                .accessibilityLabel("Styling this look")
            }
        }
        .clipped()
    }
}

/// Up to four garment photos tiled to fill the frame.
struct GarmentCollage: View {
    let garments: [OutfitGarmentRef]

    var body: some View {
        let shown = Array(garments.prefix(4))
        GeometryReader { proxy in
            let gap: CGFloat = 2
            switch shown.count {
            case 0:
                Image(systemName: "hanger")
                    .foregroundStyle(GMColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case 1:
                tile(shown[0])
            case 2:
                VStack(spacing: gap) {
                    tile(shown[0])
                    tile(shown[1])
                }
            case 3:
                HStack(spacing: gap) {
                    tile(shown[0]).frame(width: (proxy.size.width - gap) * 0.55)
                    VStack(spacing: gap) {
                        tile(shown[1])
                        tile(shown[2])
                    }
                }
            default:
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        tile(shown[0])
                        tile(shown[1])
                    }
                    HStack(spacing: gap) {
                        tile(shown[2])
                        tile(shown[3])
                    }
                }
            }
        }
    }

    private func tile(_ piece: OutfitGarmentRef) -> some View {
        Color.white
            .overlay { GMRemoteImage(url: piece.imageURL, contentMode: .fill) }
            .clipped()
    }
}
