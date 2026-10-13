import XCTest
@testable import AgentForgeTelegramNotifier

final class AgentForgeTelegramNotifierTests: XCTestCase {
    func testDefaultOriginAndRedaction() throws {
        let client = try TelegramNotifierClient(source: "agent-a", key: "private-secret")
        XCTAssertEqual(client.origin.absoluteString, telegramNotifierDefaultOrigin)
        XCTAssertEqual(client.origin.absoluteString, "http://127.0.0.1:8818")
        XCTAssertEqual(client.source, "agent-a")
        XCTAssertFalse(client.description.contains("private-secret"))
        XCTAssertTrue(client.description.contains("[REDACTED]"))
    }

    func testCredentialIsOptionalButSourceIsRequired() throws {
        let client = try TelegramNotifierClient(source: "agent-a")
        XCTAssertTrue(client.description.contains("credential: (none)"))
        XCTAssertThrowsError(try TelegramNotifierClient(source: "   ")) { error in
            XCTAssertEqual((error as? TelegramNotifierError)?.code, "INVALID_SOURCE")
        }
    }

    func testOriginPolicyAllowsLoopbackHTTPAndRemoteHTTPS() throws {
        XCTAssertNoThrow(
            try TelegramNotifierClient(source: "agent-a", origin: "http://127.0.0.1:9876")
        )
        XCTAssertNoThrow(
            try TelegramNotifierClient(source: "agent-a", origin: "http://localhost:9876")
        )
        XCTAssertNoThrow(
            try TelegramNotifierClient(source: "agent-a", origin: "https://example.com")
        )
        XCTAssertThrowsError(
            try TelegramNotifierClient(source: "agent-a", origin: "http://example.com")
        )
        XCTAssertThrowsError(
            try TelegramNotifierClient(source: "agent-a", origin: "https://user:pass@example.com")
        )
    }

    func testPrivatePathAndUnsafeIdempotencyRejectedBeforeNetwork() async throws {
        let client = try TelegramNotifierClient(source: "agent-a", key: "good")
        do {
            _ = try await client.request(method: "GET", path: "/v1/admin/users")
            XCTFail("expected private path rejection")
        } catch let error as TelegramNotifierError {
            XCTAssertEqual(error.code, "PRIVATE_PATH")
        }

        do {
            _ = try await client.request(
                method: "POST",
                path: "/v1/notify",
                body: ["text": .string("hello")],
                idempotencyKey: "short"
            )
            XCTFail("expected idempotency validation")
        } catch let error as TelegramNotifierError {
            XCTAssertEqual(error.code, "INVALID_IDEMPOTENCY_KEY")
        }
    }
}
