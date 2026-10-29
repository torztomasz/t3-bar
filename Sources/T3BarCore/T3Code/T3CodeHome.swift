import Foundation

/// Where T3 Code keeps its files: `T3CODE_HOME`, the variable T3 Code itself honours, or `~/.t3` without it.
public struct T3CodeHome: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(url: environment["T3CODE_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".t3", directoryHint: .isDirectory))
    }

    /// One status file per provider instance.
    var caches: URL { url.appending(path: "caches", directoryHint: .isDirectory) }

    /// Written by the running server; says where it listens.
    var serverRuntimeFile: URL { url.appending(path: "userdata/server-runtime.json", directoryHint: .notDirectory) }

    /// The launcher T3 Code installs for its bundled CLI.
    var cli: URL { url.appending(path: "bin/t3", directoryHint: .notDirectory) }
}
