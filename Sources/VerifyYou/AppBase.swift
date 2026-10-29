import Foundation

/// Mirrors the browser SDK's `assertVerifyYouUrl` / `isLocalHost` /
/// `registrableDomain` (browser-sdk/web/src/client.ts) so a caller can't steer
/// the native WebView at a non-VerifyYou host via `initialize(appBase:)`.
/// https + verifyyou.com (or any subdomain of it, covering dev/staging hosts)
/// is allowed; http is only allowed for a local dev host, same as the web SDK.
func isValidAppBase(_ url: URL) -> Bool {
    guard let scheme = url.scheme, let host = url.host, !host.isEmpty else { return false }
    let local = isLocalHost(host)
    guard scheme == "https" || (scheme == "http" && local) else { return false }
    return local || host == "verifyyou.com" || host.hasSuffix(".verifyyou.com")
}

/// A dev host: loopback, *.localhost/*.local, or a private (RFC 1918) /
/// link-local LAN IP (phone-on-network dev testing) -- same allowance as the
/// web SDK's `isLocalHost`.
func isLocalHost(_ host: String) -> Bool {
    if host == "localhost" || host.hasSuffix(".localhost")
        || host == "127.0.0.1" || host == "::1" || host == "[::1]"
        || host.hasSuffix(".local")
    {
        return true
    }
    let octets = host.split(separator: ".")
    guard octets.count == 4, let a = Int(octets[0]), let b = Int(octets[1]),
        octets.allSatisfy({ Int($0) != nil })
    else { return false }
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254)
}
