import Testing
@testable import UZeeSystem

@Suite("Log")
struct LogTests {
    @Test("Loggers share one subsystem")
    func subsystem() {
        #expect(Log.subsystem == "app.uzee")
    }
}
