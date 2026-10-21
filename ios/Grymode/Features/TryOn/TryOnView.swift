import SwiftUI

/// Personal try-on: the user, from their face photo and measurements, wearing a look's exact pieces.
/// Four AI-rendered angles form a turntable — drag to turn, pinch or double-tap to zoom.
struct TryOnView: View {
    let look: OutfitLook
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: TryOnModel
    @State private var avatar = AvatarModel(api: nil)
    @State private var showAvatarSetup = false
    @State private var isZoomed = false

    init(look: OutfitLook) {
        self.look = look
        _model = State(initialValue: TryOnModel(lookId: look.id, api: nil))
    }

    var body: some View {
        NavigationStack {
            AdaptiveScrollScreen(contentWidth: .readable, accessibilityIdentifier: "screen.tryOn") { _ in
                VStack(alignment: .leading, spacing: GMSpacing.lg) {
                    GMSectionHeader(
                        overline: "Try on",
                        title: look.title,
                        message: model.session.map { "\($0.heightCm) cm · \($0.bodyBuild.title)" }
                    )
                    content
                }
            }
            .scrollDisabled(isZoomed)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tryOn.done")
                }
            }
            .sheet(isPresented: $showAvatarSetup) {
                AvatarSetupSheet(avatar: avatar) {
                    Task { await model.start() }
                }
            }
            .task {
                model.bind(api: app.apiClient)
                avatar.bind(api: app.apiClient)
                await model.start()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .starting:
            GMLoadingStateView(message: "Preparing your try-on…")
        case .needsAvatar(let message):
            VStack(alignment: .leading, spacing: GMSpacing.md) {
                Text(message)
                    .gmTextStyle(.body)
                    .foregroundStyle(GMColor.textPrimary)
                Button("Finish fit profile") {
                    Task {
                        await avatar.refresh()
                        showAvatarSetup = true
                    }
                }
                .buttonStyle(.gmPrimary)
                .accessibilityIdentifier("tryOn.setupAvatar")
            }
            .gmCard(padding: GMSpacing.lg)
        case .failed(let error):
            GMErrorStateView(error: error) {
                Task { await model.start() }
            }
        case .loaded:
            if let session = model.session {
                if session.previewMode == .aiMultiView {
                    multiView(session)
                } else {
                    PersonalPreview(session: session)
                    Text(session.notice)
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func multiView(_ session: TryOnSession) -> some View {
        TryOnTurntable(session: session, isZoomed: $isZoomed)

        if let message = model.progressMessage {
            HStack(alignment: .top, spacing: GMSpacing.sm) {
                if model.isRendering {
                    ProgressView().tint(GMColor.accent)
                }
                Text(message)
                    .gmTextStyle(.callout)
                    .foregroundStyle(GMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }

        if session.status == .partial || session.status == .failed {
            Button {
                Task { await model.retry() }
            } label: {
                GMProgressLabel(title: "Try again", isWorking: model.isRetrying)
            }
            .buttonStyle(.gmSecondary)
            .disabled(model.isRetrying)
            .accessibilityIdentifier("tryOn.retry")
        }

        VStack(alignment: .leading, spacing: GMSpacing.sm) {
            Text("In this look")
                .gmTextStyle(.headline)
                .foregroundStyle(GMColor.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GMSpacing.sm) {
                    ForEach(look.orderedGarments) { piece in
                        VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                            Color.white
                                .frame(width: 88, height: 110)
                                .overlay { GMRemoteImage(url: piece.imageURL, contentMode: .fill) }
                                .clipShape(RoundedRectangle(cornerRadius: GMRadius.sm, style: .continuous))
                            Text(piece.displayName)
                                .gmTextStyle(.caption)
                                .foregroundStyle(GMColor.textPrimary)
                                .lineLimit(2)
                                .frame(width: 88, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }

        Text(session.notice)
            .gmTextStyle(.caption)
            .foregroundStyle(GMColor.textSecondary)

        Button("Update fit profile") {
            Task {
                await avatar.refresh()
                showAvatarSetup = true
            }
        }
        .buttonStyle(.gmSecondary)
        .disabled(model.isRendering)
        .accessibilityIdentifier("tryOn.updateFitProfile")
    }
}

/// Four rendered angles arranged as a turntable. The far side reuses the near-side renders
/// mirrored so a full drag turns the person all the way round.
private struct TryOnTurntable: View {
    let session: TryOnSession
    @Binding var isZoomed: Bool

    private struct Frame: Equatable {
        let angle: TryOnAngle
        let mirrored: Bool
    }

    private static let frames: [Frame] = [
        Frame(angle: .front, mirrored: false),
        Frame(angle: .threeQuarter, mirrored: false),
        Frame(angle: .side, mirrored: false),
        Frame(angle: .back, mirrored: false),
        Frame(angle: .side, mirrored: true),
        Frame(angle: .threeQuarter, mirrored: true),
    ]
    private static let pointsPerFrame: CGFloat = 44

    @State private var frameIndex = 0
    @State private var dragStartIndex: Int?
    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panAtGestureStart: CGSize = .zero

    private var frame: Frame { Self.frames[frameIndex] }

    var body: some View {
        VStack(spacing: GMSpacing.sm) {
            stage
            anglePicker
        }
    }

    private var stage: some View {
        RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
            .fill(GMColor.surfaceSunken)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                ZStack {
                    ForEach(TryOnAngle.allCases) { angle in
                        if let url = readyURL(angle) {
                            GMRemoteImage(url: url, contentMode: .fill)
                                .scaleEffect(x: frame.angle == angle && frame.mirrored ? -1 : 1, y: 1)
                                .opacity(frame.angle == angle ? 1 : 0)
                        }
                    }
                    if readyURL(frame.angle) == nil {
                        pendingOverlay
                    }
                }
                .scaleEffect(zoom)
                .offset(pan)
                .animation(.easeInOut(duration: 0.16), value: frameIndex)
            }
            .clipShape(RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
                    .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
            )
            .overlay(alignment: .bottom) {
                if zoom == 1, session.readyCount > 1 {
                    Label("Drag to turn · pinch to zoom", systemImage: "hand.draw")
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textPrimary)
                        .padding(.horizontal, GMSpacing.sm)
                        .padding(.vertical, GMSpacing.xxs)
                        .background(GMColor.surface.opacity(0.9))
                        .clipShape(Capsule())
                        .padding(GMSpacing.sm)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    setZoom(zoom > 1 ? 1 : 2)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("You wearing this look, \(frame.angle.accessibilityTitle)")
            .accessibilityAddTraits(.isImage)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(by: 1)
                case .decrement: step(by: -1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("tryOn.turntable")
    }

    @ViewBuilder
    private var pendingOverlay: some View {
        let render = session.render(for: frame.angle)
        ZStack {
            if let front = readyURL(.front) {
                GMRemoteImage(url: front, contentMode: .fill)
                    .blur(radius: 12)
                    .opacity(0.45)
            }
            VStack(spacing: GMSpacing.sm) {
                if render?.status == .failed {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(GMColor.textSecondary)
                    Text("The \(frame.angle.accessibilityTitle.lowercased()) couldn't render.")
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textPrimary)
                } else {
                    ProgressView().tint(GMColor.accent)
                    Text("Rendering \(frame.angle.accessibilityTitle.lowercased())…")
                        .gmTextStyle(.callout)
                        .foregroundStyle(GMColor.textPrimary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(GMSpacing.lg)
        }
    }

    private var anglePicker: some View {
        HStack(spacing: GMSpacing.xs) {
            ForEach(TryOnAngle.allCases) { angle in
                GMChoiceChip(title: angle.title, isSelected: frame.angle == angle, expands: true) {
                    if let index = Self.frames.firstIndex(of: Frame(angle: angle, mirrored: false)) {
                        frameIndex = index
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if session.render(for: angle)?.status.isInFlight ?? true, readyURL(angle) == nil {
                        Circle()
                            .fill(GMColor.accent)
                            .frame(width: 6, height: 6)
                            .padding(GMSpacing.xxs)
                    }
                }
                .accessibilityLabel(angle.accessibilityTitle)
                .accessibilityIdentifier("tryOn.angle.\(angle.rawValue)")
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if zoom > 1 {
                    pan = CGSize(
                        width: panAtGestureStart.width + value.translation.width,
                        height: panAtGestureStart.height + value.translation.height
                    )
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let start = dragStartIndex ?? frameIndex
                dragStartIndex = start
                let steps = Int((-value.translation.width / Self.pointsPerFrame).rounded(.towardZero))
                frameIndex = Self.wrapped(start + steps)
            }
            .onEnded { _ in
                dragStartIndex = nil
                panAtGestureStart = pan
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                setZoom(zoomAtGestureStart * value.magnification)
            }
            .onEnded { _ in
                zoomAtGestureStart = zoom
                if zoom <= 1.01 {
                    withAnimation(.spring(duration: 0.3)) { setZoom(1) }
                }
            }
    }

    private func setZoom(_ value: CGFloat) {
        zoom = min(max(value, 1), 3)
        zoomAtGestureStart = zoom
        if zoom == 1 {
            pan = .zero
            panAtGestureStart = .zero
        }
        isZoomed = zoom > 1
    }

    private func step(by delta: Int) {
        frameIndex = Self.wrapped(frameIndex + delta)
    }

    private func readyURL(_ angle: TryOnAngle) -> URL? {
        guard let render = session.render(for: angle), render.status == .succeeded else { return nil }
        return render.imageURL
    }

    private static func wrapped(_ index: Int) -> Int {
        let count = frames.count
        return ((index % count) + count) % count
    }
}

/// Face + garment composition used when AI rendering isn't configured on the server.
private struct PersonalPreview: View {
    let session: TryOnSession

    var body: some View {
        VStack(spacing: GMSpacing.md) {
            Circle()
                .fill(GMColor.surfaceSunken)
                .frame(width: 120, height: 120)
                .overlay {
                    GMRemoteImage(url: session.faceURL, failureSystemImage: "person.crop.circle")
                        .clipShape(Circle())
                }
                .overlay(Circle().strokeBorder(GMColor.border, lineWidth: GMBorder.hairline))
                .accessibilityLabel("Your face")

            VStack(spacing: GMSpacing.sm) {
                ForEach(Array(session.garmentURLs.enumerated()), id: \.offset) { index, url in
                    RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                        .fill(GMColor.surfaceSunken)
                        .aspectRatio(index == 0 ? 4 / 5 : 3 / 4, contentMode: .fit)
                        .frame(maxWidth: index == session.garmentURLs.count - 1 ? 160 : .infinity)
                        .overlay { GMRemoteImage(url: url) }
                        .clipShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
                }
            }
        }
        .padding(GMSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(GMColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GMRadius.lg, style: .continuous)
                .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
        )
    }
}
