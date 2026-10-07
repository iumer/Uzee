import SwiftUI

/// Empty state: system ContentUnavailableView, one sentence, at most one action (DESIGN_SYSTEM §15).
public struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(_ title: String, systemImage: String, description: String,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        }
    }
}

/// Loading placeholder: the real layout redacted, shimmering unless Reduce Motion is on.
public struct SkeletonCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    public init() {}

    public var body: some View {
        UZCard {
            VStack(alignment: .leading, spacing: UZSpacing.m) {
                Text("Available balance").font(.footnote)
                Text("Rs 000,000").font(.title2.bold())
                Text("Rs 000,000 + $000 · USD at 280").font(.caption)
            }
            .redacted(reason: .placeholder)
        }
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// Strip for things that need attention: overdue (negative), over budget (warning), neutral reminders.
/// Words and a symbol always accompany the colour.
public struct AlertStrip: View {
    public enum Kind: Sendable {
        case error, warning, info

        var color: Color {
            switch self {
            case .error: UZColor.negative
            case .warning: UZColor.warning
            case .info: UZColor.tint
            }
        }

        var symbol: String {
            switch self {
            case .error: "exclamationmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }
    }

    let kind: Kind
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let onDismiss: (() -> Void)?

    public init(_ kind: Kind, title: String, message: String? = nil, actionTitle: String? = nil,
                action: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: UZSpacing.l) {
            Image(systemName: kind.symbol)
                .font(.title3)
                .foregroundStyle(kind.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold))
                if let message {
                    Text(message).font(.footnote).foregroundStyle(UZColor.label2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(kind.color)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(UZColor.label2)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, UZSpacing.xxl)
        .padding(.vertical, UZSpacing.ml)
        .padding(.trailing, onDismiss == nil ? UZSpacing.xxl : UZSpacing.xs)
        .background(kind.color.opacity(0.12), in: .rect(cornerRadius: UZRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
