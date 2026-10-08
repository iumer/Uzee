import SwiftUI

/// Opaque content card: `card` fill, 20 pt continuous corners, 16 pt padding, no shadow (DESIGN_SYSTEM §14).
public struct UZCard<Content: View>: View {
    let padding: CGFloat
    /// A soft wash of colour over the card (red for money you owe, green for money owed to you).
    let tint: Color?
    let content: Content

    public init(padding: CGFloat = UZSpacing.xxl, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: UZRadius.card, style: .continuous)
                ZStack {
                    shape.fill(UZColor.card)
                    if let tint { shape.fill(tint.opacity(0.12)) }
                }
            }
    }
}

/// Section header above cards: `title3` bold, marked as a header for VoiceOver.
public struct SectionHeader: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
