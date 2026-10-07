import SwiftUI
import UZeeCore

/// Fixed category colours (DESIGN_SYSTEM §2, AUD-16). Never pick category colours per screen.
public struct CategoryStyle: Sendable {
    public let color: Color
    /// Glyph colour on the 15 % tile; darker in light mode so the symbol keeps contrast.
    public let glyph: Color
    public let symbolName: String

    public init(_ kind: CategoryKind) {
        symbolName = kind.symbolName
        switch kind {
        case .office, .entertainment:
            color = Color(uiColor: .systemIndigo); glyph = .dynamic(light: 0x5856D6, dark: 0x5E5CE6)
        case .transport:
            color = Color(uiColor: .systemBlue); glyph = .dynamic(light: 0x007AFF, dark: 0x0A84FF)
        case .food:
            color = Color(uiColor: .systemOrange); glyph = .dynamic(light: 0xC93400, dark: 0xFF9F0A)
        case .personal:
            color = Color(uiColor: .systemTeal); glyph = .dynamic(light: 0x1E7F91, dark: 0x40C8E0)
        case .utilities:
            color = Color(uiColor: .systemYellow); glyph = .dynamic(light: 0xA07800, dark: 0xFFD60A)
        case .subscriptions:
            color = Color(uiColor: .systemPink); glyph = .dynamic(light: 0xD70045, dark: 0xFF375F)
        case .financial:
            color = Color(uiColor: .systemMint); glyph = .dynamic(light: 0x00A39B, dark: 0x63E6E2)
        case .health:
            color = Color(uiColor: .systemRed); glyph = .dynamic(light: 0xD70015, dark: 0xFF453A)
        case .income, .charity:
            color = Color(uiColor: .systemGreen); glyph = .dynamic(light: 0x248A3D, dark: 0x30D158)
        case .transfer, .other:
            color = Color(uiColor: .systemGray); glyph = .dynamic(light: 0x6C6C70, dark: 0x98989D)
        case .people, .family:
            color = Color(uiColor: .systemPurple); glyph = .dynamic(light: 0x8E3CB8, dark: 0xBF5AF2)
        case .housing:
            color = Color(uiColor: .systemBrown); glyph = .dynamic(light: 0x7F6545, dark: 0xAC8E68)
        case .education:
            color = Color(uiColor: .systemCyan); glyph = .dynamic(light: 0x0071A4, dark: 0x64D2FF)
        }
    }

    /// Hex of the light-mode system colour, for tests and docs (UI-007).
    public static func lightHex(_ kind: CategoryKind) -> UInt32 {
        switch kind {
        case .office, .entertainment: 0x5856D6
        case .transport: 0x007AFF
        case .food: 0xFF9500
        case .personal: 0x30B0C7
        case .utilities: 0xFFCC00
        case .subscriptions: 0xFF2D55
        case .financial: 0x00C7BE
        case .health: 0xFF3B30
        case .income, .charity: 0x34C759
        case .transfer, .other: 0x8E8E93
        case .people, .family: 0xAF52DE
        case .housing: 0xA2845E
        case .education: 0x32ADE6
        }
    }
}

/// 36 pt category tile for rows (48 pt in the Add sheet). Decorative: the name is always beside it.
public struct CategoryTile: View {
    let kind: CategoryKind
    let size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    public init(_ kind: CategoryKind, size: CGFloat = 36) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        let style = CategoryStyle(kind)
        RoundedRectangle(cornerRadius: size >= 48 ? UZRadius.chip : UZRadius.tile, style: .continuous)
            .fill(style.color.opacity(0.15))
            .frame(width: size * scale, height: size * scale)
            .overlay {
                Image(systemName: style.symbolName)
                    .font(.system(size: size * scale * 0.45, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(style.glyph)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Category tiles") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 16) {
        ForEach(CategoryKind.allCases, id: \.self) { kind in
            VStack { CategoryTile(kind); Text(kind.name).font(.caption) }
        }
    }
    .padding()
}
