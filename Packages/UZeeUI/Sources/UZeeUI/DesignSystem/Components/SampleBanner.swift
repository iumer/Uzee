import SwiftUI

/// "Sample data" banner shown on every tab while sample mode is on (DATA-001, PRV-04).
/// One action removes the sample data.
public struct SampleBanner: View {
    let onRemove: () -> Void
    @State private var confirming = false

    public init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: UZSpacing.m) {
            Image(systemName: "sparkles")
                .accessibilityHidden(true)
            Text("Sample data")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("sample.banner")
            Spacer(minLength: UZSpacing.m)
            Button("Remove") { confirming = true }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityHint("Removes only the sample entries")
                .accessibilityIdentifier("sample.remove")
        }
        .foregroundStyle(UZColor.warning)
        .padding(.horizontal, UZSpacing.xxl)
        .background(UZColor.warning.opacity(0.14), in: .rect(cornerRadius: UZRadius.field, style: .continuous))
        .padding(.horizontal, UZSpacing.xxl)
        .padding(.bottom, UZSpacing.xs)
        .confirmationDialog("Remove sample data?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Remove sample data", role: .destructive, action: onRemove)
        } message: {
            Text("Only the sample entries are removed. Anything you added yourself stays.")
        }
    }
}
