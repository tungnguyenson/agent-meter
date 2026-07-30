import Foundation

protocol CursorCredentialsReading: Sendable {
    /// Returns the raw WorkOS session JWT, or `nil` if Cursor is not signed in.
    func readAccessToken() throws -> String?
}

enum CursorKeychainError: Error, LocalizedError {
    case commandUnavailable

    var errorDescription: String? {
        "Could not run the security command to read Cursor credentials."
    }
}

/// Reads the Cursor CLI/desktop app's session token from macOS Keychain.
///
/// Cursor stores this item (service `cursor-access-token`, account
/// `cursor-user`) under its own ACL, not one Agent Meter owns. Reading it via
/// `SecItemCopyMatching` triggers a Keychain password prompt because the
/// item's ACL does not list Agent Meter; shelling out to `/usr/bin/security`
/// avoids that prompt, mirroring `KeychainService.readCredentialsViaShell`
/// for Claude Code credentials.
final class CursorKeychainReader: CursorCredentialsReading {
    func readAccessToken() throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", Constants.Cursor.keychainService,
            "-a", Constants.Cursor.keychainAccount,
            "-w"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw CursorKeychainError.commandUnavailable
        }

        // Read output before waiting (prevents deadlock on large output)
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        guard let raw = String(data: outputData, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
