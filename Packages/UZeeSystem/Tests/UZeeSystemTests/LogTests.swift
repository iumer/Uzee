// UZee · Built by iUmer Farooq
// Copyright (c) 2026 iUmer Farooq. All rights reserved. See LICENSE.

import Testing
@testable import UZeeSystem

@Suite("Log")
struct LogTests {
    @Test("Loggers share one subsystem")
    func subsystem() {
        #expect(Log.subsystem == "app.uzee")
    }
}
