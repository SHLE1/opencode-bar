import Foundation

/// Shared flexible decoder helpers for API response structs whose numeric
/// fields may arrive as Int, Double, Int64, or String.
enum FlexibleDecoder {

    static func decodeInt<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    static func decodeInt<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKeys keys: [Key]
    ) -> Int? {
        for key in keys {
            if let value = decodeInt(container, forKey: key) {
                return value
            }
        }
        return nil
    }

    static func decodeInt64<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Int64? {
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }

    static func decodeInt64<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKeys keys: [Key]
    ) -> Int64? {
        for key in keys {
            if let value = decodeInt64(container, forKey: key) {
                return value
            }
        }
        return nil
    }

    static func decodeDouble<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            if let parsed = Double(value) {
                return parsed
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("%") {
                let percentless = String(trimmed.dropLast())
                if let parsedPercent = Double(percentless) {
                    return parsedPercent / 100.0
                }
            }
        }
        return nil
    }

    static func decodeDouble<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKeys keys: [Key]
    ) -> Double? {
        for key in keys {
            if let value = decodeDouble(container, forKey: key) {
                return value
            }
        }
        return nil
    }
}
