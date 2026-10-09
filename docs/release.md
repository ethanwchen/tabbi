# Releasing Tabbi

This is everything the maintainer does to ship a Tabbi release.
One command builds, signs, notarizes and staples the app, writes the update feed and creates a draft GitHub Release.
Nothing reaches users until you click Publish release on GitHub.

## One-time setup

Do these three steps once on the Mac you release from.
`scripts/release.sh` checks all three before it builds and lists the ones still missing.

### 1. Create the Developer ID certificate

You need the Account Holder role in the Apple Developer Program to create it.

1. Open Xcode and choose **Xcode > Settings > Accounts**.
2. Select your Apple ID, then your team, and click **Manage Certificates**.
3. Click **+** and choose **Developer ID Application**.
4. Check that it is in your keychain:

   ```sh
   security find-identity -v -p codesigning
   ```

   The list shows a line like `"Developer ID Application: Your Name (TEAMID)"`.

If the list shows more than one Developer ID Application identity, set `DEVELOPER_ID` in `packaging/signing.env` to the one to use.

### 2. Store the notarization credentials

The release script notarizes with the keychain profile `tabbi` (`NOTARY_PROFILE` in `packaging/signing.env`).
If that profile already exists, skip this step.
Otherwise create an app-specific password at [account.apple.com](https://account.apple.com) and run:

```sh
xcrun notarytool store-credentials tabbi --apple-id <your Apple ID> --team-id <TEAMID>
```

notarytool asks for the app-specific password and keeps it in your keychain, where the scripts never see it.

### 3. Create the update signing key

Every update must be signed with this key, or installed copies refuse it.

1. Fetch Sparkle's tools and generate the key pair:

   ```sh
   swift package resolve
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

2. generate_keys keeps the private key in your login keychain and prints the public key.
   Paste the public key into `SPARKLE_PUBLIC_KEY` in `packaging/updates.env` and commit that change.
3. Back up the private key somewhere safe outside the repository, such as your password manager:

   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x tabbi-update-key.txt
   ```

   Without it, installed copies can never be updated again.
   On another Mac, import the backup with `generate_keys -f tabbi-update-key.txt`.

Never commit the private key.

## Ship a release

1. Set the version in `Resources/Info.plist` (`CFBundleShortVersionString`), commit and push.
   The first release is 0.1.0, which is already set.
2. With a clean working tree, run:

   ```sh
   scripts/release.sh --publish
   ```

   It checks the setup, that gh is signed in, that your commit is pushed and that no release `v<version>` exists yet.
   Then it builds a universal app, signs it with your Developer ID, notarizes and staples the app and the DMG, and writes the update zip, `appcast.xml`, the release notes and `SHA256SUMS` to `build/release/`.
   Last, it creates a draft GitHub Release `v<version>` with gh and attaches the DMG, the zip, `appcast.xml` and `SHA256SUMS`.
3. Open the draft release link that the script prints.
   Check the notes and the attached files, then click **Publish release**.
   Edits to the notes there change only the release page: the update window shows the notes inside `appcast.xml`.
   Publishing creates the tag `v<version>`.
   From then on the download link in the README and the update feed both point at the new version.
4. Update the Homebrew cask, as described below.

Without `--publish`, the script builds everything in `build/release/` and uploads nothing, which is a good way to try a release first.

## What the release contains

- `Tabbi-<version>.dmg`: the download for new users.
- `Tabbi-<version>.zip`: the update that installed copies download.
- `appcast.xml`: the update feed.
  Installed copies read it from `https://github.com/ethanwchen/tabbi/releases/latest/download/appcast.xml` (`SPARKLE_FEED_URL` in `packaging/updates.env`), so it always comes from the latest published release.
- `SHA256SUMS`: checksums of the DMG and the zip.
- `release-notes.md`: the notes, written from the commit history by `scripts/release-notes.sh`.
  The draft release and the update window both show them.
  Only `feat`, `fix` and `perf` commits since the previous release appear, and the first release gets a short welcome instead.
- `tabbi.rb`: the Homebrew cask for this DMG (it stays local).

The build number (`CFBundleVersion`) is the commit count, so every release needs a full clone.

## Homebrew

The cask lives in the tap repository `ethanwchen/homebrew-tap`, so users install with `brew install --cask ethanwchen/tap/tabbi`.

To create the tap once:

1. Create a public GitHub repository named `homebrew-tap` under `ethanwchen`.
2. Add a `Casks` folder to it.

For each release, after you publish it:

1. Copy `build/release/tabbi.rb` to `Casks/tabbi.rb` in the tap, commit and push.
2. Check it:

   ```sh
   brew tap ethanwchen/tap
   brew trust ethanwchen/tap
   brew audit --cask --online ethanwchen/tap/tabbi
   brew install --cask ethanwchen/tap/tabbi
   ```

   Homebrew 7 refuses to load a cask from a tap you have not trusted, which `brew trust` (or installing by the full name) takes care of.
   The online audit checks that the DMG and the appcast can be downloaded, so run it only after the release is published.

Tabbi updates itself, so the cask says `auto_updates true` and `brew upgrade` leaves installed copies alone.
Once Tabbi meets Homebrew's notability rules, the same cask can be submitted to `homebrew/cask`, after which `brew install --cask tabbi` works.

## Release from GitHub Actions instead

The **Release** workflow (Actions > Release > Run workflow) runs the same script on a GitHub runner.
It needs the repository secrets listed at the top of `.github/workflows/release.yml`: the Developer ID certificate exported as a .p12, the notarization Apple ID, team id and app-specific password, and the private update key.
Turn on **publish** to create the draft release there.

## Test builds without a Developer ID

`scripts/release.sh --adhoc` builds everything without a Developer ID, the notary service or the update key.
The app is ad-hoc signed and not notarized, so macOS blocks its first launch on other Macs.
Use it only for testing; `--publish` refuses an ad-hoc build.
CI runs it on every push to main.
