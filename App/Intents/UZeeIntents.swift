import AppIntents
import UZeeUI

/// "Hey Siri, ask UZee" (VOX-01): answers from the data on this iPhone without opening the app.
struct AskUZeeIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask UZee" }
    static var description: IntentDescription { IntentDescription("Ask about your money: what you owe, your next bill, budget left, spending or a balance.") }

    @Parameter(title: "Question", requestValueDialog: IntentDialog("What would you like to know?"))
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await AppContainer.shared.session.answer(question)
        return .result(dialog: "\(answer)")
    }
}

/// "Hey Siri, add to UZee" (VOX-04, VOX-07): opens Ask UZee with the sentence, so the card can be checked before saving.
struct AddToUZeeIntent: AppIntent {
    static var title: LocalizedStringResource { "Add to UZee" }
    static var description: IntentDescription { IntentDescription("Log an expense, income, transfer, loan or repayment in one sentence. UZee opens so you can check it.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "What to add", requestValueDialog: IntentDialog("What should I add?"))
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult {
        AppContainer.shared.session.openVoice(request)
        return .result()
    }
}

/// Opens Ask UZee ready to listen (Action Button, Control Center via Shortcuts).
struct OpenAskUZeeIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Ask UZee" }
    static var description: IntentDescription { IntentDescription("Opens Ask UZee in the app.") }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppContainer.shared.session.openVoice()
        return .result()
    }
}

struct UZeeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskUZeeIntent(),
                    phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) a question", "Ask \(.applicationName) about my money"],
                    shortTitle: "Ask UZee", systemImageName: "waveform")
        AppShortcut(intent: AddToUZeeIntent(),
                    phrases: ["Add to \(.applicationName)", "Log in \(.applicationName)", "Add an expense to \(.applicationName)"],
                    shortTitle: "Add to UZee", systemImageName: "plus.circle")
        AppShortcut(intent: OpenAskUZeeIntent(),
                    phrases: ["Open \(.applicationName) voice", "Talk to \(.applicationName)"],
                    shortTitle: "Open Ask UZee", systemImageName: "mic")
    }
}
