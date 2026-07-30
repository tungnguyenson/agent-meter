import Foundation

/// Claims Agent Meter reads from the WorkOS session JWT Cursor stores in
/// Keychain. `subject` is the account identifier the `cursor.com` web API
/// expects in the session cookie; it is not the same as the integer
/// `authInfo.userId` Cursor's own CLI config stores locally, which the API
/// silently ignores. See `docs/providers/cursor.md`.
struct CursorSessionToken: Equatable {
    let subject: String
    let expiresAt: Date?

    static func decode(_ jwt: String) -> CursorSessionToken? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2,
              let payload = base64URLDecode(String(segments[1])),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let subject = claims["sub"] as? String,
              !subject.isEmpty else {
            return nil
        }
        let expiresAt = (claims["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return CursorSessionToken(subject: subject, expiresAt: expiresAt)
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
