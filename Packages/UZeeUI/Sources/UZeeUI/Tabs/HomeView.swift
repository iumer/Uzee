import SwiftUI
import UZeeCore

/// Home (SCR-02). M1: title, toolbar and the "no accounts" state; cards arrive with data in M2–M8.
struct HomeView: View {
    @Bindable var session: AppSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(UZColor.label2)
                    .accessibilityIdentifier("home.date")
                if !session.isDatabaseReady {
                    AlertStrip(.error, title: "Couldn't open your data",
                               message: "Close UZee and open it again. Nothing has been changed.")
                        .accessibilityIdentifier("home.databaseError")
                }
                UZCard {
                    EmptyStateView("No accounts yet", systemImage: "building.columns",
                                   description: "Add the bank, wallet and USD accounts you use. Your balance and what's due before salary appear here.")
                }
                .accessibilityIdentifier("home.empty")
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle("Home")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    session.isVoicePresented = true
                } label: {
                    Image(systemName: "mic")
                }
                .accessibilityLabel("Ask UZee")
                .accessibilityIdentifier("home.voice")
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("home.settings")
            }
        }
    }
}
