# SendTo ScreenMate for iOS

Send what's on your iPhone (a YouTube video, a web page, a Maps place or an address) to an Android screen in your car running [ScreenMate Receiver](https://github.com/dillonblair/SendToScreenMate-Receiver).

- **Share sheet:** Share → SendTo ScreenMate sends immediately and closes.
- **Shortcuts action:** "Send to ScreenMate" runs in the background, so it works from an NFC tag, Back Tap, the Action button or Siri.
- **End-to-end encrypted:** AES-256-GCM with a key that only your phone and your screen know.
- **No account, no backend of our own:** messages travel through [ntfy](https://ntfy.sh) (public or self-hosted), and the server only ever sees ciphertext.

## Build and install

Requires Xcode 16 or later and an iPhone on iOS 18 or later. A free Apple ID works for personal installs.

1. Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and set:
   - `BUNDLE_PREFIX`: a reverse-DNS prefix you control, e.g. `com.yourname`
   - `DEVELOPMENT_TEAM`: your Team ID (Xcode → Settings → Accounts)

   `Local.xcconfig` is git-ignored, so your personal values never end up in the repo. Avoid picking a team in Xcode's *Signing & Capabilities* tab; that writes your Team ID into the project file.
2. Open `SendToScreenMate.xcodeproj`, select the **SendToScreenMate** scheme and your iPhone, and press ⌘R.
3. On the car screen, open ScreenMate Receiver. In the iPhone app, tap **Scan QR code** (or pick a photo of the code, or paste the pairing text).

## Shortcuts and NFC

Example automation (Shortcuts → Automation → **+** → NFC):

1. **Get On-Screen URLs**
2. **Get On-Screen Postal Addresses**
3. **Text** containing both results
4. **Send to ScreenMate** with Content = Text

Optionally add **Take Screenshot** and pass it as the action's *Screenshot*: when the on-screen content has no link or place, the screenshot is read on-device for one.

Apps that don't expose their content to Shortcuts (YouTube, for example) work through the share sheet instead.

### Siri

Say **"Send this to ScreenMate"** while a page is open. With Apple Intelligence, Siri may pass the on-screen page straight to the action's *Web Page* input, which carries the full address. Shortcuts that read the screen themselves only see the domain Safari displays, so for Safari pages use this phrase or the share sheet.

## Wire protocol

| Item | Format |
|---|---|
| Pairing code | `server|topic|base64Key` (shown as a QR code by the Receiver) |
| Payload | JSON `{"url": "...", "title": "..."}` |
| Encrypted body | Base64(12-byte nonce ‖ AES-256-GCM ciphertext ‖ 16-byte tag) |
| Publish | `POST <server>/<topic>` |
| Receipt | the Receiver publishes the message id to `<server>/<topic>_ack` |

Apple Maps links and plain addresses are converted to `geo:0,0?q=…` so Android navigation apps understand them.

## Project layout

```
App/             SwiftUI app, QR pairing, Shortcuts action
ShareExtension/  share sheet extension
Shared/          protocol, encryption, link parsing, publisher, pairing storage (used by all targets)
Tests/           unit tests (run in CI on every push)
Config/          xcconfig, Info.plists, entitlements
Scripts/         project generator
```

Source folders are synchronized with the Xcode project, so adding a Swift file needs no project change. If targets or build settings change, regenerate the project with `python3 Scripts/generate_project.py`.

## License

MIT. See [LICENSE](LICENSE).
