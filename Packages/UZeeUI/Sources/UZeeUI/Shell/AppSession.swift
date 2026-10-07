import SwiftUI
import UZeeCore

/// App-wide UI state: navigation per tab, sample mode, toasts. Data work is injected
/// as closures so UZeeUI stays independent of the database package (ARCHITECTURE layers).
@MainActor
@Observable
public final class AppSession {
    public struct SampleDataActions: Sendable {
        public var isActive: @Sendable () throws -> Bool
        public var load: @Sendable () throws -> Void
        public var removeAll: @Sendable () throws -> Int

        public init(isActive: @escaping @Sendable () throws -> Bool,
                    load: @escaping @Sendable () throws -> Void,
                    removeAll: @escaping @Sendable () throws -> Int) {
            self.isActive = isActive
            self.load = load
            self.removeAll = removeAll
        }

        /// No database: sample mode stays off.
        public static let unavailable = SampleDataActions(isActive: { false }, load: {}, removeAll: { 0 })
    }

    public let info: AppInfo
    public let isDatabaseReady: Bool
    public let toasts = ToastCenter()

    public var selectedTab: AppTab = .home
    public var paths: [AppTab: [Route]] = [:]
    public var isAddPresented = false
    public var isVoicePresented = false
    public private(set) var isSampleMode = false
    /// Last error shown to the user, in plain words (DESIGN_SYSTEM §15).
    public var errorMessage: String?

    private let sampleData: SampleDataActions

    public init(info: AppInfo, isDatabaseReady: Bool, sampleData: SampleDataActions) {
        self.info = info
        self.isDatabaseReady = isDatabaseReady
        self.sampleData = sampleData
        isSampleMode = (try? sampleData.isActive()) ?? false
    }

    /// Binding for the TabView: choosing "+" opens the Add sheet instead of switching tabs.
    public var tabSelection: Binding<AppTab> {
        Binding(
            get: { self.selectedTab },
            set: { newValue in
                if newValue == .add {
                    self.isAddPresented = true
                } else {
                    self.selectedTab = newValue
                }
            }
        )
    }

    public func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    public func turnOnSampleData() {
        do {
            try sampleData.load()
            isSampleMode = true
            toasts.show("Sample data on")
        } catch {
            errorMessage = "Couldn't turn on sample data. Try again."
        }
    }

    public func removeSampleData() {
        do {
            _ = try sampleData.removeAll()
            isSampleMode = false
            toasts.show("Sample data removed")
        } catch {
            errorMessage = "Couldn't remove sample data. Nothing was changed. Try again."
        }
    }
}
