import Foundation
import UIKit

/// The web SDK's `VyResult`, field for field. `verified` is a UI hint only;
/// always confirm `token` server-side (`GET /v3/confirmations/{token}`).
public struct VyResult: Equatable {
    public let token: String?
    public let verified: Bool
    public let vyc: String?

    /// What `vyget()` returns before any run has completed, as the web SDK does.
    public static let empty = VyResult(token: nil, verified: false, vyc: nil)
}

/// A live `vycheck()`. `close()` dismisses it early and reports `onClose`; a
/// no-op once the run has settled.
public protocol VyCheckHandle: AnyObject {
    func close()
}

/// iOS shell over the web SDK (`@verifyyou-sdk/client`): same init/vycheck/vyget
/// shape and semantics. The flow runs in app-fe's native host page, which calls
/// the web SDK's `vycheck({ session, mode: "iframe" })` and reports how it
/// settled; this type only presents that page and relays the result.
public enum VerifyYou {
    /// app-fe's origin, where the host page and the flow it frames are served.
    public static let defaultAppBase = URL(string: "https://app.verifyyou.com")!

    /// Opt-in: enables Safari Web Inspector attachment to the hosted flow's WebView (iOS 16.4+). Off by default -- a shipped app should not leave this attachable in release builds.
    public static var webInspectorEnabled = false

    private static var appBase: URL = defaultAppBase
    private static var lastResult = VyResult.empty
    private static var active: CheckHandle?

    /// Optional: point the SDK at a non-production app-fe (dev, staging, a LAN
    /// dev server). Anything that isn't https on verifyyou.com, or a local dev
    /// host, is a developer mistake: it fails an assertion and the previous
    /// appBase stays in effect.
    public static func initialize(appBase: URL = defaultAppBase) {
        guard isValidAppBase(appBase) else {
            assertionFailure(
                "VerifyYou: appBase must be an https VerifyYou URL (got \(appBase.absoluteString)) -- keeping \(self.appBase.absoluteString)"
            )
            return
        }
        self.appBase = appBase
    }

    /// Opens `session` (the `session_id` your server got from a secret-key
    /// `POST /v3/initialize`) full screen. Exactly one of `onComplete`,
    /// `onClose`, `onError` fires per call, on the main queue.
    @discardableResult
    public static func vycheck(
        from presenter: UIViewController,
        session: String,
        theme: String = "auto",
        onComplete: @escaping (VyResult) -> Void,
        onClose: (() -> Void)? = nil,
        onError: ((String) -> Void)? = nil
    ) -> VyCheckHandle {
        let handle = CheckHandle()
        handle.finish = { outcome in
            if active === handle { active = nil }
            switch outcome {
            case .complete(let result):
                lastResult = result
                onComplete(result)
            case .close:
                onClose?()
            case .error(let message):
                onError?(message)
            case .ready:
                break
            }
        }

        if active != nil {
            handle.fail("a verification is already in progress")
            return handle
        }
        let trimmed = session.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            handle.fail("session must not be empty")
            return handle
        }
        guard
            let url = hostURL(
                appBase: appBase, session: trimmed, theme: resolveTheme(theme, presenter: presenter))
        else {
            handle.fail("could not build the hosted verification URL")
            return handle
        }

        active = handle
        let controller = VerificationViewController(url: url) { outcome in
            if case .ready = outcome { handle.ready = true } else { handle.settle(outcome) }
        }
        handle.controller = controller
        // Runs on the handle, not the screen: a dropped present() frees the screen,
        // and a watchdog on it would die with it.
        handle.startReadyTimer()
        DispatchQueue.main.async {
            guard !handle.settled else { return }
            // UIKit drops a present() over another one, from a screen that is not in a
            // window, or from one being dismissed, which would leave this run active
            // with no screen. Checked here, not above, so a retry from a callback sees
            // the previous screen already gone.
            if presenter.presentedViewController != nil {
                handle.settle(.error("a verification is already in progress"))
                return
            }
            if presenter.viewIfLoaded?.window == nil || presenter.isBeingDismissed {
                handle.settle(.error("could not open the verification screen"))
                return
            }
            presenter.present(controller, animated: true)
        }
        return handle
    }

    /// The last completed result, or `VyResult.empty`. In memory only, like the
    /// web SDK's iframe mode -- confirm the token on your server as soon as
    /// `onComplete` fires rather than reading it back later.
    public static func vyget() -> VyResult { lastResult }

    /// "light"/"dark" pass through; "auto" reads the presenter's appearance.
    private static func resolveTheme(_ theme: String, presenter: UIViewController) -> String {
        switch theme {
        case "light", "dark": return theme
        default: return presenter.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
        }
    }
}

/// Same constant on Android: how long after `vycheck` before `vy:ready` is given up on.
private let readyTimeout: TimeInterval = 20

private final class CheckHandle: VyCheckHandle {
    var settled = false
    var ready = false
    var finish: ((BridgeMessage) -> Void)?
    weak var controller: VerificationViewController?

    // `active` holds the handle until it settles, so the timer needs no weak capture.
    func startReadyTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + readyTimeout) { [self] in
            guard !settled, !ready else { return }
            let message = "the verification page did not start"
            if let controller { controller.fail(message) } else { settle(.error(message)) }
        }
    }

    func close() {
        DispatchQueue.main.async { [self] in
            guard !settled else { return }
            if let controller {
                controller.requestClose()
            } else {
                settle(.close)
            }
        }
    }

    func settle(_ outcome: BridgeMessage) {
        guard !settled else { return }
        settled = true
        finish?(outcome)
        finish = nil
    }

    func fail(_ message: String) {
        DispatchQueue.main.async { [self] in settle(.error(message)) }
    }
}
