import Foundation
import os

/// The accounts of every cliproxy hub connected in T3 Code, with their usage.
///
/// T3 Code polls its hubs itself but keeps their readings in memory and sends them only to clients of its server,
/// so this subscribes to the server's config stream. Nothing to set up: it mints its own read-only token with T3
/// Code's bundled CLI, the way T3 Code's own `t3 thread` commands reach the server.
///
/// The stream is T3 Code's internal RPC rather than a published API, so it is best effort: when T3 Code is closed
/// or speaks a protocol this does not, the last hubs seen are kept, and it tries again later.
public final class T3CodeHubs: Sendable {
    private let home: T3CodeHome
    private let latest = OSAllocatedUnfairLock<[T3CodeHub]>(initialState: [])
    private let connection = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    /// Waits this long after the stream ends or cannot open, which is mostly while T3 Code is closed.
    static let retryDelay: Duration = .seconds(30)

    public init(home: T3CodeHome = T3CodeHome()) {
        self.home = home
    }

    /// The hubs as T3 Code last reported them; empty until it has.
    public var hubs: [T3CodeHub] {
        latest.withLock { $0 }
    }

    /// Keeps a subscription open for the app's lifetime, calling `onChange` whenever T3 Code reports different
    /// hubs. Calling it again does nothing.
    public func start(onChange: @escaping @Sendable () -> Void) {
        connection.withLock { task in
            guard task == nil else { return }
            task = Task.detached { [self] in await keepSubscribed(onChange: onChange) }
        }
    }

    /// Stores `hubs`, telling whether they differ from what was stored.
    func update(_ hubs: [T3CodeHub]) -> Bool {
        latest.withLock { stored in
            defer { stored = hubs }
            return stored != hubs
        }
    }

    // A token outlives a connection (T3 Code restarts, Mac sleeps), so it is minted again only when refused.
    private func keepSubscribed(onChange: @escaping @Sendable () -> Void) async {
        var token: String?
        while !Task.isCancelled {
            do {
                let origin = try serverOrigin()
                let issued = if let token { token } else { try await mintToken() }
                token = issued
                try await subscribe(origin: origin, token: issued, onChange: onChange)
            } catch T3CodeServerError.unauthorized {
                token = nil
                logger.notice("T3 Code refused the token; minting a new one")
            } catch {
                logger.info("No stream from T3 Code: \(error.localizedDescription, privacy: .public)")
            }
            try? await Task.sleep(for: Self.retryDelay)
        }
    }

    /// The origin the running server wrote down, e.g. `http://127.0.0.1:3773`.
    private func serverOrigin() throws -> URL {
        struct RuntimeState: Decodable { let origin: URL }
        do {
            return try JSONDecoder().decode(RuntimeState.self, from: Data(contentsOf: home.serverRuntimeFile)).origin
        } catch {
            throw T3CodeServerError.notRunning
        }
    }

    /// `orchestration:read` is the narrowest scope that may subscribe to the config stream. A day's lifetime bounds
    /// a token the app never stores; the server ends the stream when it expires, and the next connection mints one.
    private func mintToken() async throws -> String {
        let process = Process()
        process.executableURL = home.cli
        process.arguments = ["auth", "session", "issue", "--scope", "orchestration:read", "--ttl", "1d",
                             "--label", "T3 Bar", "--token-only"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let token = try await Task.detached {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
        guard process.terminationStatus == 0, !token.isEmpty, !token.contains(where: \.isWhitespace) else {
            throw T3CodeServerError.noToken
        }
        return token
    }

    /// Returns when the server ends the stream or the connection drops.
    private func subscribe(origin: URL, token: String, onChange: @escaping @Sendable () -> Void) async throws {
        var request = URLRequest(url: T3CodeServerMessage.streamURL(origin: origin))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        // The config snapshot that opens the stream runs to a few hundred kilobytes.
        socket.maximumMessageSize = 16 * 1024 * 1024
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        do {
            try await socket.send(.string(T3CodeServerMessage.subscribeRequest))
            logger.notice("Subscribed to T3 Code's hubs")
            while true {
                let frame = try await T3CodeServerMessage(socket.receive())
                if let hubs = frame.hubs, update(hubs) {
                    onChange()
                }
                if frame.needsAck {
                    try await socket.send(.string(T3CodeServerMessage.ack))
                }
                if frame.endsStream { return }
            }
        } catch {
            if (socket.response as? HTTPURLResponse)?.statusCode == 401 { throw T3CodeServerError.unauthorized }
            throw error
        }
    }
}

/// One cliproxy hub as T3 Code reports it.
public struct T3CodeHub: Equatable, Sendable {
    public let id: String
    /// What T3 Code shows for it: the label the user gave it, or the hub's host.
    public let label: String
    /// Empty when T3 Code could not read the hub; its error says why.
    public let accounts: [T3CodeHubAccount]
}

/// One account in a hub's pool, e.g. one of several Claude subscriptions.
public struct T3CodeHubAccount: Equatable, Sendable {
    /// The hub's own id for it, stable while the account stays in the hub.
    public let id: String
    /// `claudeAgent` or `codex`, as T3 Code names the provider underneath.
    public let driver: String
    public let email: String?
    public let usage: T3CodeUsage?
}

enum T3CodeServerError: Error, LocalizedError {
    case notRunning
    case noToken
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notRunning: "T3 Code is not running."
        case .noToken: "T3 Code's CLI did not issue a token."
        case .unauthorized: "T3 Code refused the token."
        }
    }
}

private let logger = Logger(subsystem: "com.torz.t3bar", category: "T3CodeHubs")
