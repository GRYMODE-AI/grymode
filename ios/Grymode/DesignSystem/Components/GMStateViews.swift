import SwiftUI

/// A real action attached to a state view. State views never show a button without one.
struct GMStateAction {
    let title: String
    let perform: () -> Void
}

struct GMEmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var action: GMStateAction?

    var body: some View {
        VStack(spacing: GMSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: GMSize.iconLarge, weight: .light))
                .foregroundStyle(GMColor.accent)
                .accessibilityHidden(true)
            Text(title)
                .gmTextStyle(.headline)
                .foregroundStyle(GMColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .gmTextStyle(.body)
                .foregroundStyle(GMColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.gmSecondary)
                    .padding(.top, GMSpacing.xs)
            }
        }
        .frame(maxWidth: 420)
        .padding(.vertical, GMSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct GMErrorStateView: View {
    let error: AppError
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: GMSpacing.md) {
            Image(systemName: error == .offline ? "wifi.slash" : "exclamationmark.circle")
                .font(.system(size: GMSize.iconLarge, weight: .light))
                .foregroundStyle(GMColor.error)
                .accessibilityHidden(true)
            Text(error.title)
                .gmTextStyle(.headline)
                .foregroundStyle(GMColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(error.userMessage)
                .gmTextStyle(.body)
                .foregroundStyle(GMColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry, error.isRetryable {
                Button("Try again", action: retry)
                    .buttonStyle(.gmSecondary)
                    .padding(.top, GMSpacing.xs)
            }
            if let requestID = error.requestID {
                Text("Reference: \(requestID)")
                    .gmTextStyle(.caption)
                    .foregroundStyle(GMColor.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: 420)
        .padding(.vertical, GMSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct GMLoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: GMSpacing.md) {
            ProgressView()
                .tint(GMColor.accent)
            Text(message)
                .gmTextStyle(.callout)
                .foregroundStyle(GMColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, GMSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
