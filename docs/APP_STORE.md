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

## Beta App Review notes (App Store Connect → TestFlight → Test Information)
> NO QR CODE NEEDED: on the first screen, tap "Try Without a Q2". Every tab opens without signing in: edit the
> EQ (drag the dots or the curve), search Presets for any headphones and open one, and use Response to draw a
> squig.link measurement and run AutoEQ. Only the Card tab and playing the EQ on the player need a Q2.
>
> EQ Studio for Q2 is a remote control for the Shanling Q2, a portable music player running the open-source Q2 Pod
> firmware and its EQ Studio app (github.com/DiamondBond/q2-eq-studio). There is no account: the app pairs with the
> player on the same network, or the user's own Tailscale, by scanning the QR code the Q2 shows on its own screen,
> or with its PIN. A video of that flow with a real Q2 was sent in our reply to the review of build 1.
>
> App Transport Security: EQ Studio on the Q2 serves plain HTTP at the player's own address on the user's network
> (a 192.168.x.x or Tailscale 100.x address, or a Tailscale name). `NSAllowsArbitraryLoads` lets the app reach the
> address the user scans or types; it contacts no other HTTP host.
>
> The app is open source (GPL-3.0): github.com/js-surya/q2-eq-studio-ios. Not affiliated with Shanling.

Build 0.1.0 (1) was rejected under guideline 2.1 ("we need a demo QR code"): the reviewer has no Q2. Build 3 added
Try Without a Q2 for that, and the reply attached a video of the app with a real Q2. Keep Try Without a Q2 working:
it's how every review gets past the first screen.

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
