# App Store submission notes

**Name:** EQ Studio for Q2 (the home screen shows "EQ Studio"; "EQ Studio" alone may be taken in the App Store)
**Subtitle:** Shape your Q2's EQ live
**Category:** Music
**Platforms:** iOS / iPadOS 26+
**Bundle ID:** `me.suryajs.eqstudio` · **SKU:** `eqstudio`
**Export compliance:** `ITSAppUsesNonExemptEncryption = NO` in Info.plist (HTTPS only, exempt)

## Positioning
A native app for EQ Studio (github.com/DiamondBond/q2-eq-studio), the Q2 Pod app that edits the Shanling Q2's
parametric EQ. Its EQ logic is EQ Studio's, ported with the permission of EQ Studio's and Q2 Theme Studio's
authors, who allow it on TestFlight and the App Store (GPL-3.0 with their exception). The icon is EQ Studio's own,
used with permission. Not affiliated with Shanling: say so in the description and in review notes.

## Beta App Review notes (paste into App Store Connect → TestFlight → Test Information)
> EQ Studio for Q2 controls the EQ of a Shanling Q2 music player running the open-source Q2 Pod firmware and its
> EQ Studio app. It needs that player on the same network (or the user's own Tailscale) to sign in: the Q2 shows
> a QR code and a PIN. A video of the app working with a Q2 is attached: [link].
> Without a Q2, the Presets tab still searches AutoEq's catalogue, and Response draws squig.link measurements.
> App Transport Security: EQ Studio on the Q2 serves plain HTTP at the player's own address on the user's
> network (a 192.168.x.x or Tailscale 100.x address, or a Tailscale name). `NSAllowsArbitraryLoads` lets the app
> reach the address the user scans or types; it contacts no other HTTP host.

## Privacy
- Privacy policy URL: https://github.com/js-surya/q2-eq-studio-ios/blob/main/docs/PRIVACY.md
- App Privacy questionnaire: "Data Not Collected".
- The privacy manifest ships in the app (`App/PrivacyInfo.xcprivacy`).

## Before uploading
1. Paid Apple Developer Program membership, signed in to Xcode → Settings → Accounts with that Apple ID;
   set the team in `Config/Signing.xcconfig`.
2. Create the app in App Store Connect → Apps → + → New App: iOS, the name above, bundle ID
   `me.suryajs.eqstudio`, SKU `eqstudio`.
3. Set the version and build with `scripts/set-version.sh X.Y.Z BUILD` (each upload needs a new build number).
4. Archive (`scripts/archive.sh`, or Product → Archive), then upload from Xcode's Organizer: Window → Organizer
   → the archive → Distribute App → App Store Connect → Upload. Organizer signs with your Xcode account;
   `scripts/archive.sh --upload` needs an App Store Connect user that can sign in the cloud.
5. In TestFlight: internal testers (people on the team) get it as soon as it's processed; external testers and
   a public link need Beta App Review first (the notes above).
6. Screenshots (for the App Store, later): iPhone 6.9" and iPad 13". In Debug, `EQS_LINK=<link>` signs in to
   EQ Studio running on a computer, and `EQS_TAB`, `EQS_QUERY`, `EQS_PRESET` open the screens.

## Licence note
GPL-3.0-only, as EQ Studio is, with its authors' permission for TestFlight and App Store distribution.
Third-party: AutoEq's presets (MIT), credited in About → Acknowledgements.
