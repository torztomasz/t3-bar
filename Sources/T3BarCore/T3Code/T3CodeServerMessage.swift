import Foundation

/// One frame of T3 Code's WebSocket RPC (Effect RPC, one JSON object per text frame), read for what the hub
/// subscription needs: whether to acknowledge it, the hubs it carries, and whether the stream is over.
struct T3CodeServerMessage {
    /// Set when the frame carries a `usageLimitSourcesUpdated` event; T3 Code sends one right after subscribing.
    let hubs: [T3CodeHub]?
    /// The server sends a stream's next chunk only once the client has acknowledged the last one.
    let needsAck: Bool
    let endsStream: Bool

    /// The server checks the protocol version by exact match and refuses an upgrade without it.
    static func streamURL(origin: URL) -> URL {
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        components?.scheme = origin.scheme == "https" ? "wss" : "ws"
        components?.path = "/ws"
        components?.queryItems = [URLQueryItem(name: "orchestrationProtocol", value: "2")]
        return components?.url ?? origin
    }

    /// `usageLimitSources` opts in to hub readings; `workspaceSnapshotsOnDemand` leaves out per-folder provider
    /// snapshots, which the app does not need, to keep frames small.
    static let subscribeRequest = """
        {"_tag":"Request","id":"\(requestID)","tag":"subscribeServerConfig",\
        "payload":{"usageLimitSources":true,"workspaceSnapshotsOnDemand":true},"headers":[]}
        """
    static let ack = #"{"_tag":"Ack","requestId":"\#(requestID)"}"#
    private static let requestID = "1"

    /// An unreadable frame, or one of a kind the app does not use, changes nothing.
    init(_ message: URLSessionWebSocketTask.Message) {
        let data: Data = switch message {
        case .string(let text): Data(text.utf8)
        case .data(let data): data
        @unknown default: Data()
        }
        let frame = try? JSONDecoder.t3Code.decode(Frame.self, from: data)
        let isOurs = frame?.requestId == Self.requestID
        hubs = isOurs ? frame?.values?.last { $0.type == "usageLimitSourcesUpdated" }?.sources : nil
        needsAck = isOurs && frame?.tag == "Chunk"
        endsStream = isOurs && frame?.tag == "Exit"
    }

    private struct Frame: Decodable {
        let tag: String
        let requestId: String?
        let values: [Event]?

        enum CodingKeys: String, CodingKey {
            case tag = "_tag", requestId, values
        }
    }

    /// Lenient per event: a snapshot or settings event the app cannot read must not cost it the hub event beside it.
    private struct Event: Decodable {
        let type: String?
        let sources: [T3CodeHub]?

        enum CodingKeys: String, CodingKey { case type, payload }
        enum PayloadKeys: String, CodingKey { case sources }

        init(from decoder: any Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            type = try? container?.decode(String.self, forKey: .type)
            let payload = try? container?.nestedContainer(keyedBy: PayloadKeys.self, forKey: .payload)
            sources = (try? payload?.decode([Source].self, forKey: .sources))?.map(\.hub)
        }
    }

    private struct Source: Decodable {
        let id: String
        let label: String
        /// Decoded one by one, so an account shaped in a way the app does not know costs that account, not the hub.
        let accounts: [Lossy<Account>]
        let error: String?

        struct Account: Decodable {
            let id: String
            let driver: String
            let email: String?
            let usageLimits: T3CodeUsageLimits?
        }

        var hub: T3CodeHub {
            T3CodeHub(id: id, label: label, accounts: accounts.compactMap(\.value).map {
                T3CodeHubAccount(id: $0.id, driver: $0.driver, email: $0.email, usage: $0.usageLimits?.usage)
            }, error: error)
        }
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }
}
