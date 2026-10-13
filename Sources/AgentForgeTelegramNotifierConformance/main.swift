import AgentForgeTelegramNotifier
import Foundation

@main
struct Conformance {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("fixture origin required")
        }

        let origin = CommandLine.arguments[1]
        let client = try TelegramNotifierClient(
            source: "agent-a",
            key: "good-secret",
            origin: origin,
            timeout: 2,
            retries: 1
        )

        let notification = try await client.notify("hello notify")
        precondition((notification["deliveryId"] ?? notification["delivery_id"])?.stringValue == "d1")

        let reply = try await client.reply(eventID: "e1", text: "reply", idempotencyKey: "stable-reply-123")
        precondition((reply["deliveryId"] ?? reply["delivery_id"])?.stringValue == "d1" || (reply["deliveryId"] ?? reply["delivery_id"])?.stringValue == "d2")

        let inbox = try await client.inbox(limit: 10)
        let items = (inbox["events"] ?? inbox["items"])?.arrayValue ?? []
        precondition(items.first?.objectValue?["id"]?.stringValue == "e1")

        let file = try await client.download(eventID: "e1")
        precondition(["f.txt", "hello.txt"].contains(file.filename))
        precondition(file.contentType == "text/plain")
        precondition(["file-body", "hello-file"].contains(String(data: file.content, encoding: .utf8) ?? ""))

        let quota = try TelegramNotifierClient(
            source: "agent-a",
            key: "quota-secret",
            origin: origin,
            timeout: 2,
            retries: 0
        )
        do {
            _ = try await quota.inbox()
            fatalError("quota request unexpectedly succeeded")
        } catch let error as TelegramNotifierError {
            precondition(error.code == "QUOTA_EXCEEDED")
            precondition(error.kind == .quota)
            precondition(error.retryAfterSeconds == 30)
            precondition(!error.description.contains("quota-secret"))
        }

        let bad = try TelegramNotifierClient(
            source: "agent-a",
            key: "bad-secret",
            origin: origin,
            timeout: 2,
            retries: 0
        )
        do {
            _ = try await bad.inbox()
            fatalError("bad credential unexpectedly succeeded")
        } catch let error as TelegramNotifierError {
            precondition(error.kind == .auth)
            precondition(!error.description.contains("bad-secret"))
        }

        print("SWIFT_TELEGRAM_NOTIFIER_CONFORMANCE=PASS")
    }
}
