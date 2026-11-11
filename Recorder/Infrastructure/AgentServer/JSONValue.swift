import Foundation

/// Any JSON value, for JSON-RPC messages whose parameters and results vary by method.
enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else {
            return nil
        }
        return members[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let members) = self else {
            return nil
        }
        return members
    }

    /// Compact UTF-8, keys sorted so the same value always gives the same bytes.
    func encoded() throws -> Data {
        try JSONEncoder.sortedCompact.encode(self)
    }

    static func decoded(from data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Converts any encodable value, using the encoder's key and date strategies.
    static func converting<Value: Encodable>(_ value: Value, with encoder: JSONEncoder) throws -> JSONValue {
        try decoded(from: encoder.encode(value))
    }
}

extension JSONValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Identifiers and counts are integers; writing them without a fraction keeps them integers for clients.
            if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }

    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension JSONValue: ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }

    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements) { _, last in last })
    }
}

extension JSONEncoder {
    fileprivate static var sortedCompact: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
