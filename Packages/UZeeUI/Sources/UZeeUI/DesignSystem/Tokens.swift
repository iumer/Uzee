import SwiftUI
import UIKit

/// Colour tokens (DESIGN_SYSTEM §1). Feature code uses these, never raw hex.
public enum UZColor {
    public static let bg = system(light: 0xF2F2F7, dark: 0x000000, uikit: .systemGroupedBackground)
    public static let card = system(light: 0xFFFFFF, dark: 0x1C1C1E, uikit: .secondarySystemGroupedBackground)
    public static let card2 = system(light: 0xF2F2F7, dark: 0x2C2C2E, uikit: .tertiarySystemGroupedBackground)
    public static let label = Color.primary
    /// Darker than system secondaryLabel so small text keeps 4.5:1 contrast.
    public static let label2 = Color.dynamic(light: 0x6C6C70, dark: 0x98989F)
    public static let label3 = system(light: 0xC7C7CC, dark: 0x48484A, uikit: .tertiaryLabel)
    public static let separator = system(light: 0xE5E5EA, dark: 0x38383A, uikit: .separator)
    public static let fill = system(light: 0xE9E9EB, dark: 0x2C2C2E, uikit: .tertiarySystemFill)
    public static let tint = Color.accentColor
    public static let positive = Color.dynamic(light: 0x248A3D, dark: 0x30D158)
    public static let negative = Color.dynamic(light: 0xD70015, dark: 0xFF453A)
    public static let warning = Color.dynamic(light: 0xC93400, dark: 0xFF9F0A)

    /// System semantic colour; the hex values document what the mockups use.
    static func system(light: UInt32, dark: UInt32, uikit: UIColor) -> Color { Color(uiColor: uikit) }
}

/// Spacing scale, 2 pt base (DESIGN_SYSTEM §5).
public enum UZSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 6
    public static let m: CGFloat = 8
    public static let ml: CGFloat = 10
    public static let l: CGFloat = 12
    public static let xl: CGFloat = 14
    public static let xxl: CGFloat = 16
    public static let xxxl: CGFloat = 20
}

/// Corner radii, always continuous (DESIGN_SYSTEM §6).
public enum UZRadius {
    public static let badge: CGFloat = 8
    public static let tile: CGFloat = 10
    public static let field: CGFloat = 12
    public static let control: CGFloat = 14
    public static let chip: CGFloat = 15
    public static let menu: CGFloat = 16
    public static let card: CGFloat = 20
}

/// Springs (DESIGN_SYSTEM §17). Callers pass `reduceMotion` so motion turns off with the setting.
public enum UZMotion {
    public static var press: Animation { .spring(duration: 0.35, bounce: 0.15) }
    public static var appear: Animation { .spring(duration: 0.4, bounce: 0.15) }
    public static var value: Animation { .spring(duration: 0.5, bounce: 0.1) }
    public static var toast: Animation { .spring(duration: 0.4, bounce: 0.15) }
    public static var selection: Animation { .spring(duration: 0.35, bounce: 0.2) }
    /// Reduce Motion replaces movement with a short crossfade.
    public static var reduced: Animation { .easeInOut(duration: 0.2) }

    public static func pick(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

extension Color {
    /// A colour with separate light and dark values.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
