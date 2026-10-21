import SwiftUI

/// Filled soft-black button for the single primary action on a screen.
struct GMPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .gmTextStyle(.button)
            .foregroundStyle(GMColor.onActionPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: GMSize.buttonHeight)
            .padding(.horizontal, GMSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .fill(GMColor.actionPrimary)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
    }
}

/// Outlined button for secondary actions.
struct GMSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .gmTextStyle(.button)
            .foregroundStyle(GMColor.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: GMSize.buttonHeight)
            .padding(.horizontal, GMSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .fill(configuration.isPressed ? GMColor.surfaceSunken : GMColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .strokeBorder(GMColor.border, lineWidth: GMBorder.hairline)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
    }
}

/// Text-only button for low-emphasis actions such as "Skip".
struct GMTertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .gmTextStyle(.button)
            .foregroundStyle(GMColor.textSecondary)
            .frame(minHeight: GMSize.minTapTarget)
            .padding(.horizontal, GMSpacing.xs)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// Filled oxblood button reserved for irreversible actions such as deleting the account.
struct GMDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .gmTextStyle(.button)
            .foregroundStyle(GMColor.onActionPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: GMSize.buttonHeight)
            .padding(.horizontal, GMSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous)
                    .fill(GMColor.error)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: GMRadius.md, style: .continuous))
    }
}

extension ButtonStyle where Self == GMDestructiveButtonStyle {
    static var gmDestructive: GMDestructiveButtonStyle { GMDestructiveButtonStyle() }
}

extension ButtonStyle where Self == GMPrimaryButtonStyle {
    static var gmPrimary: GMPrimaryButtonStyle { GMPrimaryButtonStyle() }
}

extension ButtonStyle where Self == GMSecondaryButtonStyle {
    static var gmSecondary: GMSecondaryButtonStyle { GMSecondaryButtonStyle() }
}

extension ButtonStyle where Self == GMTertiaryButtonStyle {
    static var gmTertiary: GMTertiaryButtonStyle { GMTertiaryButtonStyle() }
}
