# VerifyYou iOS SDK

Human verification for iOS apps. The SDK opens the hosted VerifyYou flow full screen. The flow proves that a user is a real, unique, live human.

This repository is a release mirror. Each release replaces its contents. Changes made here are overwritten.

## Requirements

- iOS 15 or later
- Swift 5.9 or later (Xcode 15 or later)
- `NSCameraUsageDescription` in your app's own Info.plist (see below)

## Install

In Xcode:

1. Open File, then Add Package Dependencies.
2. Paste `https://github.com/VerifyYou/verifyyou-ios` in the search field.
3. Choose a version rule. Up to Next Major Version is a good default.
4. Add the `VerifyYou` library to your app target.

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/VerifyYou/verifyyou-ios", from: "1.0.0-rc.1")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            // package: is the last part of the URL, without ".git"
            .product(name: "VerifyYou", package: "verifyyou-ios")
        ]
    )
]
```

## Camera permission

The verification flow uses the camera. Add `NSCameraUsageDescription` to your app's own Info.plist with a short reason for the user. A package cannot add this key for you.

If the key is missing, iOS ends your app as soon as the camera is requested.

## Use

Create a session on your server with `POST /v3/initialize`. Then pass the session id to the SDK.

```swift
import VerifyYou

VerifyYou.vycheck(from: self, session: sessionId, onComplete: { result in
    // Send result.token to your server and confirm it there.
})
```

## More

Full guides and the server API are at https://docs.verifyyou.com.

## License

MIT. See `LICENSE`.
