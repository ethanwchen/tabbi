import SwiftUI
import NotchKitCore

/// A designed stand-in for a module that is registered but still being built.
///
/// Kits can list a module before its feature lands, so its tab must still
/// look intentional: the module's identity and pitch on the left, what it
/// will do on the right. Each module's own panel file wraps this, so the
/// feature can later replace that one file without touching shared code.
public struct ModulePreview: View {
    /// One planned capability, shown as a row in the feature card.
    public struct Feature: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        public var id: String { title }

        public init(symbol: String, title: String, detail: String) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
        }
    }

    let module: ModuleID
    let pitch: String
    let features: [Feature]

    public init(module: ModuleID, pitch: String, features: [Feature]) {
        self.module = module
        self.pitch = pitch
        self.features = features
    }

    private var accent: Color { Theme.Palette.accent(for: module) }

    public var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            hero
            featureCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: module.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(accent.opacity(0.16))
                )
            // The header already names the tab, so the pitch leads.
            Text(pitch)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            Text("In development")
                .font(Theme.Typography.caption)
                .foregroundStyle(accent)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Capsule(style: .continuous).fill(accent.opacity(0.14)))
                .help("\(module.title) is part of this kit and arrives in an upcoming update")
        }
        .frame(width: 196, alignment: .leading)
    }

    private var featureCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(features) { feature in
                    FeatureRow(feature: feature, accent: accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct FeatureRow: View {
    let feature: ModulePreview.Feature
    let accent: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: feature.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                        .fill(accent.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 0) {
                Text(feature.title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(feature.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            .lineLimit(1)
        }
        .frame(maxHeight: .infinity)
    }
}
