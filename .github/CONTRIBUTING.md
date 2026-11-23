# Contributing to EQ Studio for iPhone and iPad

Thanks for helping! A few things keep the project healthy.

## Before you start
- For anything bigger than a small fix, open an issue first so we can agree on the approach.
- Every feature must work on iPhone and iPad.
- The app does what [EQ Studio](https://github.com/DiamondBond/q2-eq-studio)'s page does, no more: a new feature
  belongs in EQ Studio first. Its logic (`web/*.js`) is ported into `Packages/EQCore` with its tests, GPL-3.0.

## Setting up
1. Install Xcode 27+ and XcodeGen (`brew install xcodegen`).
2. `cp Config/Signing.xcconfig.example Config/Signing.xcconfig` and set your Team ID.
3. Run `xcodegen generate` and open `EQStudio.xcodeproj`. If you change `project.yml`, generate again.
4. To try it without a Q2, run EQ Studio on your computer (its README, Building) and start the app in
   the simulator with `EQS_LINK=<the link EQ Studio prints>`.

## Code
- Logic goes in `Packages/EQCore` with tests; the app stays thin.
- Write the test first, watch it fail, then make it pass.
- Run `scripts/test.sh` before opening a pull request.

## Commits
Short, conventional messages such as `fix(eq): …` or `feat(presets): …`, with the issue number when there is one.

## Branches and releases
- `main` holds released code. `develop` collects work for the next release.
- Every change goes on its own branch and into **`develop`** through a pull request. Run `scripts/test.sh` first.
- **To release:** on `develop`, set the version and build with `scripts/set-version.sh X.Y.Z BUILD` and commit,
  then open a pull request from `develop` into `main`. **Merge it with a regular merge, not squash**: GitHub then
  publishes "EQ Studio X.Y.Z (BUILD)" (tag `vX.Y.Z`, or `vX.Y.Z-BUILD` for a later build of the same version)
  with the source code and notes listing every change since the previous release. The app itself is
  distributed only through TestFlight and the App Store.
- Docs-only changes don't start a release.
