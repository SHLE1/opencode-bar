import Foundation

/// Shared ISO 8601 date parsing with fractional-seconds fallback.
/// Many API responses include fractional seconds (e.g. "2026-02-05T14:59:30.123Z")
/// that the basic ISO8601DateFormatter cannot parse without explicit options.
enum ISO8601DateParsing {

    private static let formatterWithFractional: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private static let formatterWithoutFractional: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    /// Parses an ISO 8601 date string, trying fractional seconds first, then without.
    static func parse(_ dateString: String) -> Date? {
        formatterWithFractional.date(from: dateString)
            ?? formatterWithoutFractional.date(from: dateString)
    }

    /// Formats a Date to ISO 8601 string (without fractional seconds).
    static func string(from date: Date) -> String {
        formatterWithoutFractional.string(from: date)
    }
}
