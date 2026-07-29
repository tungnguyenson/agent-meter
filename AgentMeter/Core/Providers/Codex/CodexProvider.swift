import Foundation
import Darwin

struct CodexBinaryResolver {
    static let minimumVersion = [0, 146, 0]

    let configuredPath: String?
    let homeDirectory: URL
    let environmentPath: String
    let fileManager: FileManager

    init(
        configuredPath: String? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        fileManager: FileManager = .default
    ) {
        self.configuredPath = configuredPath
        self.homeDirectory = homeDirectory
        self.environmentPath = environmentPath
        self.fileManager = fileManager
    }

    func resolve() -> URL? {
        candidatePaths()
            .map(\.standardizedFileURL)
            .first { isTrustedCandidate($0) }
    }

    func validateVersion(at binaryURL: URL) -> Result<String, CodexAppServerError> {
        guard let version = Self.readVersion(at: binaryURL) else {
            return .failure(.unsupportedVersion("unknown"))
        }
        return Self.isSupported(version)
            ? .success(version)
            : .failure(.unsupportedVersion(version))
    }

    static func isSupported(_ version: String) -> Bool {
        let components = version
            .split(separator: ".")
            .prefix(3)
            .compactMap { Int($0.filter(\.isNumber)) }
        guard components.count == 3 else { return false }
        return components.lexicographicallyPrecedes(minimumVersion) == false
    }

    private func candidatePaths() -> [URL] {
        var paths: [URL] = []
        if let configuredPath, !configuredPath.isEmpty {
            paths.append(URL(fileURLWithPath: configuredPath))
        }
        paths += environmentPath
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        paths.append(homeDirectory.appendingPathComponent(".local/bin/codex"))
        paths += nvmCandidates()
        paths += [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        return unique(paths)
    }

    private func nvmCandidates() -> [URL] {
        let root = homeDirectory.appendingPathComponent(".nvm/versions/node")
        guard let versions = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return versions
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .map { $0.appendingPathComponent("bin/codex") }
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func isTrustedExecutable(_ url: URL) -> Bool {
        guard fileManager.isExecutableFile(atPath: url.path),
              isRegularFile(url),
              trustedPathComponents(for: url).allSatisfy(hasSafeOwnershipAndPermissions) else {
            return false
        }
        return true
    }

    private func isTrustedCandidate(_ candidate: URL) -> Bool {
        let resolvedExecutable = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedLauncherDirectory = candidate
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return isTrustedExecutable(resolvedExecutable)
            && trustedPathComponents(for: resolvedLauncherDirectory)
                .allSatisfy(hasSafeOwnershipAndPermissions)
    }

    private func isRegularFile(_ url: URL) -> Bool {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeRegular
    }

    private func trustedPathComponents(for executable: URL) -> [URL] {
        let home = homeDirectory.resolvingSymlinksInPath().standardizedFileURL
        let executablePath = executable.standardizedFileURL.path
        let isInsideHome = executablePath.hasPrefix(home.path + "/")
        let boundary = isInsideHome ? home : URL(fileURLWithPath: "/")
        var components = [executable]
        var current = executable.deletingLastPathComponent()
        while current.path.count >= boundary.path.count {
            components.append(current)
            if current.standardizedFileURL == boundary.standardizedFileURL {
                break
            }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return components
    }

    private func hasSafeOwnershipAndPermissions(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let owner = attributes[.ownerAccountID] as? NSNumber,
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        let ownerID = owner.uint32Value
        let mode = permissions.uint16Value
        return (ownerID == 0 || ownerID == getuid()) && (mode & 0o022 == 0)
    }

    private static func readVersion(at binaryURL: URL) -> String? {
        let process = Process()
        let output = Pipe()
        let capture = CodexVersionOutputCapture(maxBytes: 4_096)
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = binaryURL
        process.arguments = ["--version"]
        process.environment = CodexProcessEnvironment.environment(for: binaryURL)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            capture.append(handle.availableData)
        }
        process.terminationHandler = { _ in completion.signal() }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        guard completion.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            if completion.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        output.fileHandleForReading.readabilityHandler = nil
        capture.append(output.fileHandleForReading.readDataToEndOfFile())
        let data = capture.data
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
            .split(whereSeparator: { $0.isWhitespace })
            .last
            .map(String.init)
    }
}

enum CodexProcessEnvironment {
    private static let systemPathDirectories = [
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]
    private static let inheritedKeys = [
        "ALL_PROXY",
        "CODEX_HOME",
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "NODE_EXTRA_CA_CERTS",
        "NO_COLOR",
        "NO_PROXY",
        "SSL_CERT_DIR",
        "SSL_CERT_FILE",
        "TERM",
        "XDG_CONFIG_HOME",
        "all_proxy",
        "http_proxy",
        "https_proxy",
        "no_proxy"
    ]

    static func environment(
        for binaryURL: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let launcherDirectory = binaryURL.deletingLastPathComponent().path
        let inheritedPathDirectories = (base["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter(isTrustedNodeDirectory)
        let launcherRuntimeDirectories = isTrustedNodeDirectory(launcherDirectory)
            ? [launcherDirectory]
            : []
        let candidateDirectories = launcherRuntimeDirectories
            + inheritedPathDirectories
            + systemPathDirectories
        let path = candidateDirectories.enumerated()
            .filter { offset, directory in
                candidateDirectories.firstIndex(of: directory) == offset
            }
            .map(\.element)
            .joined(separator: ":")
        let inherited = Dictionary(
            uniqueKeysWithValues: inheritedKeys.compactMap { key in
                base[key].map { (key, $0) }
            }
        )
        return inherited.merging([
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": path,
            "TMPDIR": FileManager.default.temporaryDirectory.path
        ]) { _, required in required }
    }

    private static func isTrustedSearchDirectory(_ path: String) -> Bool {
        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return false
        }

        let home = fileManager.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let isInsideHome = directory.path.hasPrefix(home.path + "/")
        let boundary = isInsideHome ? home : URL(fileURLWithPath: "/")
        var current = directory
        while current.path.count >= boundary.path.count {
            guard hasSafeOwnershipAndPermissions(current, fileManager: fileManager) else {
                return false
            }
            if current == boundary { return true }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return false }
            current = parent
        }
        return false
    }

    private static func isTrustedNodeDirectory(_ path: String) -> Bool {
        guard isTrustedSearchDirectory(path) else { return false }
        let fileManager = FileManager.default
        let node = URL(fileURLWithPath: path)
            .appendingPathComponent("node")
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard fileManager.isExecutableFile(atPath: node.path),
              let attributes = try? fileManager.attributesOfItem(atPath: node.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              hasSafeOwnershipAndPermissions(node, fileManager: fileManager) else {
            return false
        }
        return isTrustedSearchDirectory(node.deletingLastPathComponent().path)
    }

    private static func hasSafeOwnershipAndPermissions(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let owner = attributes[.ownerAccountID] as? NSNumber,
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        let ownerID = owner.uint32Value
        let mode = permissions.uint16Value
        return (ownerID == 0 || ownerID == getuid()) && (mode & 0o022 == 0)
    }
}

private final class CodexVersionOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private var storage = Data()

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, maxBytes - storage.count)
        storage.append(data.prefix(remaining))
    }
}

final class CodexProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .codex
    let metadata = ProviderMetadata(
        id: .codex,
        displayName: "Codex",
        shortName: "Codex",
        symbolName: "chevron.left.forwardslash.chevron.right"
    )

    private let resolver: CodexBinaryResolver
    private let clientFactory: @Sendable (URL) -> any CodexAppServerServing
    private let lock = NSLock()
    private var cachedClient: (any CodexAppServerServing)?

    init(
        resolver: CodexBinaryResolver = CodexBinaryResolver(),
        clientFactory: @escaping @Sendable (URL) -> any CodexAppServerServing = {
            CodexAppServerClient(binaryURL: $0)
        }
    ) {
        self.resolver = resolver
        self.clientFactory = clientFactory
    }

    func configurationStatus() async -> ProviderConfigurationStatus {
        guard let binaryURL = resolver.resolve() else {
            return .unavailable(CodexAppServerError.binaryNotFound.localizedDescription)
        }
        switch resolver.validateVersion(at: binaryURL) {
        case .success:
            return .ready
        case .failure(let error):
            return .unavailable(error.localizedDescription)
        }
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        let client = try client()
        async let accountResult = optional { try await client.readAccount() }
        let rateLimits = try await client.readRateLimits()
        let account = await accountResult

        if account.map(Self.requiresAuthentication) == true {
            throw CodexAppServerError.authenticationRequired
        }

        return CodexUsageMapper.snapshot(
            rateLimits: rateLimits,
            account: account?.account
        )
    }

    func shutdown() async {
        let client = takeCachedClient()
        await client?.stop()
    }

    private func takeCachedClient() -> (any CodexAppServerServing)? {
        lock.lock()
        defer { lock.unlock() }
        let client = cachedClient
        cachedClient = nil
        return client
    }

    private func client() throws -> any CodexAppServerServing {
        lock.lock()
        defer { lock.unlock() }
        if let cachedClient { return cachedClient }
        guard let binaryURL = resolver.resolve() else {
            throw CodexAppServerError.binaryNotFound
        }
        if case .failure(let error) = resolver.validateVersion(at: binaryURL) {
            throw error
        }
        let client = clientFactory(binaryURL)
        cachedClient = client
        return client
    }

    private func optional<T>(_ operation: () async throws -> T) async -> T? {
        try? await operation()
    }

    static func requiresAuthentication(_ response: CodexAccountResponse) -> Bool {
        response.requiresOpenaiAuth && response.account == nil
    }
}
