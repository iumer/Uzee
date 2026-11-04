// UZee · Built by iUmer Farooq
// Copyright (c) 2026 iUmer Farooq. All rights reserved. See LICENSE.

import os

/// Central loggers. Interpolated values are private by default in os.Logger,
/// so amounts, names and notes show as <private> outside a debugger (ENV-008).
/// Never mark financial values `.public`.
public enum Log {
    public static let subsystem = "app.uzee"
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let data = Logger(subsystem: subsystem, category: "data")
    public static let system = Logger(subsystem: subsystem, category: "system")
}
