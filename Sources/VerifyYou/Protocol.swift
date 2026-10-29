import Foundation

/// Wire contract with app-fe's native host page
/// (app-fe `src/features/Embed/nativeBridge.ts`). The SDK opens
/// `<appBase>/native.html?vys=<session>&vy_bridge=1`; that page runs the web
/// SDK's own `vycheck({ session, mode: "iframe" })` and posts one JSON message
/// per state change back through `handlerName`. The SDK never builds a flow
/// URL itself. Pinned against app-fe and Android by
/// `web/test/native-bridge.contract.test.ts`.
enum Bridge {
    static let hostPath = "/native.html"
    static let bridgeParam = "vy_bridge"
    static let bridgeVersion = "1"
    static let sessionParam = "vys"
    static let themeParam = "theme"

    /// `window.webkit.messageHandlers.vy`
    static let handlerName = "vy"
    /// `window.vyClose()` — asks the web SDK to close, which answers with `vy:close`.
    static let closeFunction = "vyClose"

    static let msgReady = "vy:ready"
    static let msgComplete = "vy:complete"
    static let msgClose = "vy:close"
    static let msgError = "vy:error"
}

enum BridgeMessage: Equatable {
    /// The flow loaded inside the host page. It shows no close control there, so
    /// the native one stays up after this.
    case ready
    case complete(VyResult)
    case close
    case error(String)
}

/// Whether a scheme, host and port are `url`'s origin. Host case does not matter
/// and a default port equals its explicit form; WebKit reports a default as 0.
func isSameOrigin(scheme: String?, host: String?, port: Int?, as url: URL) -> Bool {
    func key(_ scheme: String?, _ host: String?, _ port: Int?) -> String? {
        guard let scheme = scheme?.lowercased(), let host = host?.lowercased(), !host.isEmpty else {
            return nil
        }
        let explicit = port.flatMap { $0 > 0 ? $0 : nil }
        return "\(scheme)://\(host):\(explicit ?? (scheme == "https" ? 443 : 80))"
    }
    guard let mine = key(url.scheme, url.host, url.port) else { return false }
    return mine == key(scheme, host, port)
}

/// The host page URL for a session: `<appBase origin>/native.html?vys=…`.
func hostURL(appBase: URL, session: String, theme: String) -> URL? {
    guard var components = URLComponents(url: appBase, resolvingAgainstBaseURL: false) else {
        return nil
    }
    components.path = Bridge.hostPath
    components.fragment = nil
    components.queryItems = [
        URLQueryItem(name: Bridge.sessionParam, value: session),
        URLQueryItem(name: Bridge.bridgeParam, value: Bridge.bridgeVersion),
        URLQueryItem(name: Bridge.themeParam, value: theme),
    ]
    // URLComponents leaves "+" literal; URLSearchParams (the host page) decodes it as a space.
    components.percentEncodedQuery = components.percentEncodedQuery?
        .replacingOccurrences(of: "+", with: "%2B")
    return components.url
}

/// Decodes one message the host page posted. Unknown types return nil so a
/// newer page can add messages without breaking a shipped SDK.
func parseBridgeMessage(_ body: Any) -> BridgeMessage? {
    guard let text = body as? String,
        let data = text.data(using: .utf8),
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let type = object["type"] as? String
    else { return nil }
    switch type {
    case Bridge.msgReady:
        return .ready
    case Bridge.msgComplete:
        let vyc = object["vyc"] as? String
        return .complete(VyResult(token: object["token"] as? String, verified: vyc == "1", vyc: vyc))
    case Bridge.msgClose:
        return .close
    case Bridge.msgError:
        return .error(object["message"] as? String ?? "verification failed")
    default:
        return nil
    }
}
