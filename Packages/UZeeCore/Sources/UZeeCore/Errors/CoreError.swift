/// Errors raised by domain logic. User-facing text is produced in one place
/// (UZeeUI ErrorPresentation), never from these cases directly.
public enum CoreError: Error, Equatable, Sendable {
    case invalidAmount
    case currencyMismatch
    case notFound
    case validationFailed(field: String)
}
