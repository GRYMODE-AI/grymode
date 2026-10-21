import SwiftUI

/// An inline error shown next to the control that caused it. Announced to VoiceOver when it appears.
struct GMInlineError: View {
    let error: AppError

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GMSpacing.xs) {
            Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.circle")
                .foregroundStyle(GMColor.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                Text(error.userMessage)
                    .foregroundStyle(GMColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let requestID = error.requestID {
                    Text("Reference: \(requestID)")
                        .gmTextStyle(.caption)
                        .foregroundStyle(GMColor.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .gmTextStyle(.callout)
        .padding(GMSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                .fill(GMColor.error.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inlineError")
        .onAppear {
            AccessibilityNotification.Announcement(error.userMessage).post()
        }
    }
}

/// A button label that swaps in a progress indicator while work is running, keeping its size.
struct GMProgressLabel: View {
    let title: String
    let isWorking: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(isWorking ? 0 : 1)
            if isWorking {
                ProgressView()
                    .tint(GMColor.onActionPrimary)
                    .accessibilityLabel("Working")
            }
        }
    }
}
