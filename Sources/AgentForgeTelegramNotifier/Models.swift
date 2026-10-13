import Foundation

public let telegramNotifierDefaultOrigin = "http://127.0.0.1:8818"
@available(*, deprecated, renamed: "telegramNotifierDefaultOrigin")
public let telegramNotifierManagedOrigin = telegramNotifierDefaultOrigin
public let telegramNotifierVersion = "0.2.0"

public enum TelegramNotifierErrorKind: String, Sendable {
    case auth
    case quota
    case delivery
    case validation
    case api
    case network
    case invalidResponse
    case client
}

public struct TelegramNotifierError: Error, LocalizedError, CustomStringConvertible, Sendable {
    public let kind: TelegramNotifierErrorKind
    public let status: Int
    public let code: String
    public let message: String
    public let requestID: String?
    public let retryAfterSeconds: Int?

    public init(
        kind: TelegramNotifierErrorKind,
        status: Int = 0,
        code: String,
        message: String,
        requestID: String? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.kind = kind
        self.status = status
        self.code = code
        self.message = message
        self.requestID = requestID
        self.retryAfterSeconds = retryAfterSeconds
    }

    public var errorDescription: String? { description }
    public var description: String {
        "Telegram Notifier \(code) (\(status)): \(message)"
    }
}

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

public struct DownloadedFile: Sendable, Equatable {
    public let filename: String
    public let contentType: String
    public let content: Data

    public init(filename: String, contentType: String, content: Data) {
        self.filename = filename
        self.contentType = contentType
        self.content = content
    }
}
