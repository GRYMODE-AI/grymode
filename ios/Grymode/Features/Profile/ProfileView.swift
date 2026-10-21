import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AdaptiveScrollScreen(accessibilityIdentifier: "screen.profile") { _ in
            VStack(alignment: .leading, spacing: GMSpacing.xl) {
                GMSectionHeader(overline: "Account", title: "Profile")

                AccountSection(account: model.account)

                VStack(alignment: .leading, spacing: GMSpacing.md) {
                    Text("Style")
                        .gmTextStyle(.overline)
                        .foregroundStyle(GMColor.accent)
                    Button {
                        model.router.select(.style)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                                Text("Style profile")
                                    .gmTextStyle(.bodyEmphasized)
                                    .foregroundStyle(GMColor.textPrimary)
                                Text(model.styleProfiles.profile.headline)
                                    .gmTextStyle(.callout)
                                    .foregroundStyle(GMColor.textSecondary)
                            }
                            Spacer(minLength: GMSpacing.sm)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(GMColor.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: GMSize.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.styleProfile")
                }
                .gmCard(padding: GMSpacing.lg)

                VStack(alignment: .leading, spacing: GMSpacing.sm) {
                    Text("Legal & support")
                        .gmTextStyle(.overline)
                        .foregroundStyle(GMColor.accent)
                    LegalLinkRow(title: LegalLinks.privacyTitle, url: LegalLinks.privacy)
                        .accessibilityIdentifier("profile.privacy")
                    LegalLinkRow(title: LegalLinks.termsTitle, url: LegalLinks.terms)
                        .accessibilityIdentifier("profile.terms")
                    LegalLinkRow(title: LegalLinks.supportTitle, url: LegalLinks.support)
                        .accessibilityIdentifier("profile.support")
                }
                .gmCard(padding: GMSpacing.lg)

                VStack(alignment: .leading, spacing: GMSpacing.sm) {
                    Text("About")
                        .gmTextStyle(.overline)
                        .foregroundStyle(GMColor.accent)
                    InfoRow(title: "Version", value: Bundle.main.versionDescription)
                    InfoRow(title: "Service", value: serviceStatus)
                }
                .gmCard(padding: GMSpacing.lg)

                #if DEBUG
                    DeveloperSection(model: model)
                #endif
            }
        }
    }

    private var serviceStatus: String {
        switch model.configuration {
        case .success(let configuration):
            configuration.environment == .production ? "Connected configuration" : "Development"
        case .failure:
            "Not configured"
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).foregroundStyle(GMColor.textPrimary)
                Spacer(minLength: GMSpacing.sm)
                Text(value).foregroundStyle(GMColor.textSecondary)
            }
            VStack(alignment: .leading, spacing: GMSpacing.xxs) {
                Text(title).foregroundStyle(GMColor.textPrimary)
                Text(value).foregroundStyle(GMColor.textSecondary)
            }
        }
        .gmTextStyle(.body)
        .frame(minHeight: GMSize.minTapTarget)
        .accessibilityElement(children: .combine)
    }
}

private struct LegalLinkRow: View {
    @Environment(\.openURL) private var openURL
    let title: String
    let url: URL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Text(title)
                    .gmTextStyle(.body)
                    .foregroundStyle(GMColor.textPrimary)
                Spacer(minLength: GMSpacing.sm)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GMColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: GMSize.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
    /// Development-only tools. Compiled out of Release builds.
    private struct DeveloperSection: View {
        let model: AppModel

        var body: some View {
            VStack(alignment: .leading, spacing: GMSpacing.sm) {
                Text("Developer")
                    .gmTextStyle(.overline)
                    .foregroundStyle(GMColor.accent)
                if case .success(let configuration) = model.configuration {
                    InfoRow(title: "API", value: configuration.apiBaseURL.absoluteString)
                    InfoRow(title: "Auth", value: configuration.supabaseURL.absoluteString)
                }
            }
            .gmCard(padding: GMSpacing.lg)
        }
    }
#endif
