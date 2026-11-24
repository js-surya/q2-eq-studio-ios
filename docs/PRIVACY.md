# EQ Studio for iPhone and iPad: Privacy Policy

_Last updated: 2026-11-24_

EQ Studio for iPhone and iPad is an app for [EQ Studio](https://github.com/DiamondBond/q2-eq-studio), the Q2 Pod app
that edits a Shanling Q2's EQ.

**The app collects no data.** There is no analytics, tracking or advertising, no automatic crash reporting, and no
server of the app's own.

- **Your Q2:** the app talks only to EQ Studio on your Q2, at the address you scan or type, on your Wi-Fi or over
  your own Tailscale. It sends the EQ you edit and reads the one the Q2 plays, its EQ folder's presets and
  AutoEq's catalogue from the card.
- **Signing in:** EQ Studio's key (from its QR code, or got with its PIN) is kept in the Apple Keychain on your
  device, and the Q2's addresses in the app's settings. The PIN itself is not stored. **Sign Out** removes both.
- **Without a Q2** (Try Without a Q2): the EQ stays on your device, and the list of AutoEq presets is read from
  EQ Studio's public repository on GitHub (`raw.githubusercontent.com`) without signing in; GitHub sees your IP
  address, as with any web request.
- **The camera** is used only while you scan EQ Studio's QR code, on your device. No picture is kept.
- **Response:** when you pick a measurement or a target, the app reads it from [squig.link](https://squig.link),
  without signing in; squig.link sees your IP address, as with any web request. Only which reviewer, target and
  measurement you picked is kept, on your device.
- **About:** the profile pictures of the three people credited (the developer, DiamondBond and tyleree) come from
  `github.com`, which sees your IP address, as with any
  web request.
- **Your EQ, settings, recent presets and the app's look** are kept on your device only.
- **Files** you open or share go where you choose; the app keeps no copy.
- **Clipboard:** the app reads it only when you tap Paste.

Questions: open an issue in the [repository](https://github.com/js-surya/q2-eq-studio-ios/issues).
