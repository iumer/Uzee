import AppIntents
import SwiftUI
import WidgetKit

/// Ask UZee from outside the app (VOX-01): a Control Center / Lock Screen / Action Button control and a
/// Lock Screen widget. Both open Ask UZee listening. No money data is shown, so nothing needs sharing.
@main
struct UZeeWidgets: WidgetBundle {
    var body: some Widget {
        AskUZeeControl()
        AskUZeeLockScreenWidget()
    }
}

/// The same intent as the app's (App/Intents/UZeeIntents.swift); the system runs the app's copy, which opens
/// Ask UZee. Keep the name and title in step with it.
struct OpenAskUZeeIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Ask UZee" }
    static var description: IntentDescription { IntentDescription("Opens Ask UZee in the app.") }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult { .result() }
}

struct AskUZeeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.uzee.ask") {
            ControlWidgetButton(action: OpenAskUZeeIntent()) {
                Label("Ask UZee", systemImage: "waveform")
            }
        }
        .displayName("Ask UZee")
        .description("Talk to UZee: log spending, ask about bills and balances.")
    }
}

struct AskUZeeLockScreenWidget: Widget {
    struct Entry: TimelineEntry { let date: Date }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .never))
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.uzee.ask.lock", provider: Provider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform").font(.title2.weight(.semibold))
            }
            .widgetURL(URL(string: "uzee://ask"))
            .containerBackground(.clear, for: .widget)
            .accessibilityLabel("Ask UZee")
        }
        .configurationDisplayName("Ask UZee")
        .description("Opens Ask UZee, ready to listen.")
        .supportedFamilies([.accessoryCircular])
    }
}
