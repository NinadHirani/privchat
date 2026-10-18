# PrivChat — serverless, offline, end-to-end encrypted messenger (Android + iOS)

No servers · no accounts · no phone number · no internet required.
Phones find each other on the same Wi-Fi / hotspot (and Wi-Fi Direct on Android,
Multipeer on iPhone) and talk directly, end-to-end encrypted with libsodium.

## Features
1:1 chat · group chats (admins, add/remove, rename) · voice & video calls (WebRTC, LAN only) ·
photos / videos / documents / voice notes · location + live location · contact cards ·
status (24 h) · read receipts, typing, reactions, reply, forward, delete-for-everyone ·
disappearing messages · safety-number / QR verification · biometric app lock ·
encrypted database (SQLCipher) + encrypted media vault · screenshot blocking (Android) ·
store-and-forward outbox (messages go out automatically when the contact comes back in range).

## ⚡ Download Android APK

Install PrivChat directly on your Android phone without needing to compile anything:

| Architecture | Download Link | Fast Global CDN Mirror | Size | Best For |
|---|---|---|---|---|
| **ARM64 (Recommended)** | [Direct Download](https://github.com/NinadHirani/privchat/releases/download/v1.0.0/app-arm64-v8a-release.apk) | [⚡ Fast Mirror](https://ghfast.top/https://github.com/NinadHirani/privchat/releases/download/v1.0.0/app-arm64-v8a-release.apk) | **43 MB** | 99% of modern Android phones (Samsung, Pixel, OnePlus, Xiaomi, etc.) |
| **ARM 32-bit** | [Direct Download](https://github.com/NinadHirani/privchat/releases/download/v1.0.0/app-armeabi-v7a-release.apk) | [⚡ Fast Mirror](https://ghfast.top/https://github.com/NinadHirani/privchat/releases/download/v1.0.0/app-armeabi-v7a-release.apk) | **34 MB** | Older Android devices |
| **Universal (All CPUs)** | [Direct Download](https://github.com/NinadHirani/privchat/releases/download/v1.0.0/app-release.apk) | [⚡ Fast Mirror](https://ghfast.top/https://github.com/NinadHirani/privchat/releases/download/v1.0.0/app-release.apk) | **118 MB** | Works on any device |

> **Tip:** If your standard GitHub download is slow or throttled, click the **⚡ Fast Mirror** link for high-speed download.

## Build (needs Flutter ≥ 3.22; Android Studio; Xcode on a Mac for iOS)
```bash
cd app
flutter create --org app.privchat --project-name privchat --platforms android,ios .
python3 tool/setup_platforms.py      # overlays native code + patches gradle/plist
flutter pub get
flutter test                          # Dart crypto must match Python reference vectors
flutter run                           # on a real device (emulators can't do LAN discovery)
# iOS: cd ios && pod install && cd .. && flutter run
```

## Testing two devices
Put both phones on the same Wi-Fi or one phone's hotspot (mobile data can be OFF).
They appear under *New chat → Nearby*. Verify the safety number in *Contact info*.

Laptop as a test peer (same network):
```bash
cd protocol && python3 tools/peer_cli.py --name Laptop
```

## Layout
| Path | What |
|---|---|
| `protocol/` | Python reference implementation, 17 tests, test vectors, CLI peer |
| `docs/PROTOCOL.md` | Wire protocol & threat model |
| `app/lib/core/` | crypto, networking, storage, services |
| `app/lib/ui/` | screens |
| `app/native_overlay/` | Kotlin (Wi-Fi Direct, foreground service) & Swift (Multipeer) |

## Limits (hard limits, not bugs)
* Range = one Wi-Fi network / hotspot (~30–50 m), Wi-Fi Direct ~100 m. No calls across a city without infrastructure.
* Android ↔ iPhone needs a shared Wi-Fi or hotspot (Apple and Google peer-to-peer radios don't interoperate).
* iOS can't keep listening in the background forever; recipients on iPhone must have the app open or recently used.
* Messages to someone out of range wait in your outbox until you're both near each other again.
