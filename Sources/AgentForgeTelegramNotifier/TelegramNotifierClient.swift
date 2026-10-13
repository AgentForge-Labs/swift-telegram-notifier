import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class TelegramNotifierClient: @unchecked Sendable, CustomStringConvertible {
    public let origin: URL
    public let source: String

    private let credential: String?
    private let session: URLSession
    private let timeout: TimeInterval
    private let retries: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        source: String,
        key: String? = nil,
        origin: String = telegramNotifierDefaultOrigin,
        allowCustomOrigin: Bool = false,
        allowInsecureLoopback: Bool = false,
        timeout: TimeInterval = 15,
        retries: Int = 1,
        session: URLSession = .shared
    ) throws {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty,
              !normalizedSource.contains("\r"),
              !normalizedSource.contains("\n") else {
            throw Self.clientError("INVALID_SOURCE", "source must not be empty")
        }
        guard retries >= 0 else {
            throw Self.clientError("INVALID_RETRIES", "retries must be zero or greater")
        }
        guard timeout > 0 else {
            throw Self.clientError("INVALID_TIMEOUT", "timeout must be greater than zero")
        }

        self.origin = try Self.validateOrigin(origin)
        _ = allowCustomOrigin
        _ = allowInsecureLoopback
        self.source = normalizedSource
        if let key {
            let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
            self.credential = normalized.isEmpty ? nil : normalized
        } else {
            self.credential = nil
        }
        self.session = session
        self.timeout = timeout
        self.retries = retries
    }

    public var description: String {
        let credentialState = credential == nil ? "(none)" : "[REDACTED]"
        return "TelegramNotifierClient(source: \(source), origin: \(origin.absoluteString), credential: \(credentialState), retries: \(retries))"
    }

    public func inbox(after: String? = nil, limit: Int = 50) async throws -> [String: JSONValue] {
        guard (1...500).contains(limit) else {
            throw Self.clientError("INVALID_LIMIT", "limit must be between 1 and 500")
        }
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let after, !after.isEmpty {
            query.append(URLQueryItem(name: "after", value: after))
        }
        return try await request(method: "GET", path: "/v1/inbox", query: query)
    }

    public func notify(
        _ text: String,
        title: String = "",
        idempotencyKey: String? = nil
    ) async throws -> [String: JSONValue] {
        try await request(
            method: "POST",
            path: "/v1/notify",
            body: [
                "kind": .string("text"),
                "title": .string(title),
                "text": .string(text),
            ],
            idempotencyKey: idempotencyKey
        )
    }

    public func notifyFile(
        data: Data,
        filename: String,
        contentType: String = "application/octet-stream",
        photo: Bool = false,
        caption: String = "",
        idempotencyKey: String? = nil
    ) async throws -> [String: JSONValue] {
        try Self.validateFilename(filename)
        return try await request(
            method: "POST",
            path: "/v1/notify",
            body: [
                "kind": .string(photo ? "photo" : "document"),
                "filename": .string(filename),
                "content_type": .string(contentType),
                "content_base64": .string(data.base64EncodedString()),
                "text": .string(caption),
            ],
            idempotencyKey: idempotencyKey
        )
    }

    public func reply(
        eventID: String,
        text: String,
        title: String = "",
        idempotencyKey: String? = nil
    ) async throws -> [String: JSONValue] {
        try Self.validateEventID(eventID)
        return try await request(
            method: "POST",
            path: "/v1/reply",
            body: [
                "event_id": .string(eventID),
                "kind": .string("text"),
                "title": .string(title),
                "text": .string(text),
            ],
            idempotencyKey: idempotencyKey
        )
    }

    public func replyFile(
        eventID: String,
        data: Data,
        filename: String,
        contentType: String = "application/octet-stream",
        photo: Bool = false,
        caption: String = "",
        idempotencyKey: String? = nil
    ) async throws -> [String: JSONValue] {
        try Self.validateEventID(eventID)
        try Self.validateFilename(filename)
        return try await request(
            method: "POST",
            path: "/v1/reply",
            body: [
                "event_id": .string(eventID),
                "kind": .string(photo ? "photo" : "document"),
                "filename": .string(filename),
                "content_type": .string(contentType),
                "content_base64": .string(data.base64EncodedString()),
                "text": .string(caption),
            ],
            idempotencyKey: idempotencyKey
        )
    }

    public func download(eventID: String) async throws -> DownloadedFile {
        try Self.validateEventID(eventID)
        let payload = try await request(
            method: "GET",
            path: "/v1/file",
            query: [URLQueryItem(name: "event_id", value: eventID)]
        )
        guard let encoded = payload["content_base64"]?.stringValue,
              let content = Data(base64Encoded: encoded) else {
            throw Self.invalidResponse("invalid file payload")
        }
        return DownloadedFile(
            filename: payload["filename"]?.stringValue ?? "",
            contentType: payload["content_type"]?.stringValue ?? "application/octet-stream",
            content: content
        )
    }

    public func request(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil,
        idempotencyKey: String? = nil,
        retry: Bool = true
    ) async throws -> [String: JSONValue] {
        let normalizedMethod = method.uppercased()
        guard ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(normalizedMethod) else {
            throw Self.clientError("UNSUPPORTED_METHOD", "unsupported HTTP method")
        }

        let safePath = try Self.safePath(path)
        let payload = body == nil ? nil : try encoder.encode(body)
        let key: String?
        if normalizedMethod == "GET" {
            key = nil
        } else {
            key = try Self.normalizeIdempotencyKey(idempotencyKey)
        }

        let raw = try await execute(
            method: normalizedMethod,
            path: safePath,
            query: query,
            body: payload,
            idempotencyKey: key,
            retry: retry
        )
        if raw.isEmpty { return [:] }
        do {
            return try decoder.decode([String: JSONValue].self, from: raw)
        } catch {
            throw Self.invalidResponse("invalid JSON response from Telegram Notifier")
        }
    }

    private func execute(
        method: String,
        path: String,
        query: [URLQueryItem],
        body: Data?,
        idempotencyKey: String?,
        retry: Bool
    ) async throws -> Data {
        let safeToRetry = method == "GET" || idempotencyKey != nil
        let attempts = retry && safeToRetry ? retries + 1 : 1

        for attempt in 0..<attempts {
            try Task.checkCancellation()

            guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
                throw Self.clientError("INVALID_ORIGIN", "could not construct Telegram Notifier URL")
            }
            components.path = path
            if !query.isEmpty { components.queryItems = query }
            guard let url = components.url else {
                throw Self.clientError("INVALID_PATH", "could not construct request URL")
            }

            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(source, forHTTPHeaderField: "X-Notifier-Source")
            request.setValue(
                "agentforge-telegram-notifier-swift/\(telegramNotifierVersion)",
                forHTTPHeaderField: "User-Agent"
            )
            if let credential {
                request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            }
            if body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let idempotencyKey {
                request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            }

            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else {
                    throw Self.invalidResponse("Telegram Notifier returned a non-HTTP response")
                }
                if (200..<300).contains(http.statusCode) {
                    return data
                }

                let apiError = Self.parseAPIError(
                    status: http.statusCode,
                    data: data,
                    credential: credential
                )
                let retryable = [429, 502, 503, 504].contains(http.statusCode)
                if attempt + 1 >= attempts || !retryable || apiError.code == "QUOTA_EXCEEDED" {
                    throw apiError
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as TelegramNotifierError {
                if attempt + 1 >= attempts { throw error }
                if error.code == "QUOTA_EXCEEDED" { throw error }
                if ![429, 502, 503, 504].contains(error.status) { throw error }
            } catch let error as URLError {
                if Task.isCancelled || error.code == .cancelled {
                    throw CancellationError()
                }
                if attempt + 1 >= attempts {
                    throw TelegramNotifierError(kind: .network, code: "NETWORK_ERROR", message: "network request failed")
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if attempt + 1 >= attempts {
                    throw TelegramNotifierError(kind: .network, code: "NETWORK_ERROR", message: "network request failed")
                }
            }

            let exponent = min(attempt, 3)
            let delay = UInt64(250 * (1 << exponent)) * 1_000_000
            try await Task.sleep(nanoseconds: delay)
        }

        throw TelegramNotifierError(kind: .network, code: "NETWORK_ERROR", message: "network request failed")
    }

    private static func parseAPIError(
        status: Int,
        data: Data,
        credential: String?
    ) -> TelegramNotifierError {
        let decoded = (try? JSONDecoder().decode([String: JSONValue].self, from: data)) ?? [:]
        let nestedError = decoded["error"]?.objectValue
        let payload = nestedError ?? decoded
        let explicitCode = payload["code"]?.stringValue
        let fallbackError = decoded["error"]?.stringValue
        let code = explicitCode
            ?? fallbackError?.uppercased().replacingOccurrences(of: "-", with: "_")
            ?? "HTTP_ERROR"
        let rawMessage = payload["message"]?.stringValue
            ?? fallbackError
            ?? HTTPURLResponse.localizedString(forStatusCode: status)
        let safeMessage: String
        if let credential, !credential.isEmpty {
            safeMessage = rawMessage.replacingOccurrences(of: credential, with: "[REDACTED]")
        } else {
            safeMessage = rawMessage
        }

        let kind: TelegramNotifierErrorKind
        if status == 401 || status == 403 {
            kind = .auth
        } else if code == "QUOTA_EXCEEDED" || code == "RATE_LIMITED" {
            kind = .quota
        } else if code == "DELIVERY_FAILED" {
            kind = .delivery
        } else if status == 400 || status == 404 || status == 409 || status == 422 {
            kind = .validation
        } else {
            kind = .api
        }

        let retryAfter: Int?
        if let number = payload["retryAfterSeconds"] ?? payload["retry_after_seconds"],
           case .number(let value) = number {
            retryAfter = Int(value)
        } else {
            retryAfter = nil
        }
        let requestID = payload["requestId"]?.stringValue ?? payload["request_id"]?.stringValue

        return TelegramNotifierError(
            kind: kind,
            status: status,
            code: code,
            message: safeMessage,
            requestID: requestID,
            retryAfterSeconds: retryAfter
        )
    }

    private static func validateOrigin(_ value: String) throws -> URL {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw clientError("INVALID_ORIGIN", "origin must be a valid HTTP(S) origin without credentials, path, query, or fragment")
        }

        let isLoopback = ["localhost", "127.0.0.1", "::1"].contains(host)
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw clientError("INVALID_ORIGIN", "remote origins must use HTTPS; HTTP is allowed only for loopback")
        }

        let normalized = value.hasSuffix("/") ? String(value.dropLast()) : value
        guard let url = URL(string: normalized) else {
            throw clientError("INVALID_ORIGIN", "origin must be a valid HTTP(S) origin")
        }
        return url
    }

    private static func safePath(_ path: String) throws -> String {
        guard path.hasPrefix("/v1/"),
              !path.contains("?"),
              !path.contains("#"),
              !path.contains("://") else {
            throw clientError("INVALID_PATH", "path must be a relative public /v1/* path")
        }
        guard path.removingPercentEncoding == path,
              !path.contains("\\"),
              !path.contains("//"),
              !path.split(separator: "/").contains("..") else {
            throw clientError("INVALID_PATH", "encoded or traversal paths are forbidden")
        }

        let blocked = ["/v1/admin", "/v1/internal", "/v1/saas-admin", "/v1/webhooks", "/v1/payments", "/v1/checkout"]
        let lower = path.lowercased()
        for prefix in blocked where lower == prefix || lower.hasPrefix(prefix + "/") {
            throw clientError("PRIVATE_PATH", "private paths are not available through this client")
        }
        return path
    }

    private static func validateEventID(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 200,
              !trimmed.contains("\r"),
              !trimmed.contains("\n") else {
            throw clientError("INVALID_EVENT_ID", "event ID must be a safe non-empty value")
        }
    }

    private static func validateFilename(_ value: String) throws {
        guard !value.isEmpty,
              value.count <= 255,
              value != ".",
              value != "..",
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains("\r"),
              !value.contains("\n") else {
            throw clientError("INVALID_FILENAME", "filename must be a safe basename")
        }
    }

    private static func normalizeIdempotencyKey(_ value: String?) throws -> String {
        let key = value ?? UUID().uuidString.lowercased()
        guard key.count >= 8,
              key.count <= 200,
              !key.contains("\r"),
              !key.contains("\n") else {
            throw clientError("INVALID_IDEMPOTENCY_KEY", "idempotency key must be 8-200 safe characters")
        }
        return key
    }

    private static func clientError(_ code: String, _ message: String) -> TelegramNotifierError {
        TelegramNotifierError(kind: .client, code: code, message: message)
    }

    private static func invalidResponse(_ message: String) -> TelegramNotifierError {
        TelegramNotifierError(kind: .invalidResponse, code: "INVALID_RESPONSE", message: message)
    }
}
