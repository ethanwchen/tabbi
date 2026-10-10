# Sign in with Apple and sync

Signing in is optional.
Without an account, Tabbi works exactly as before, and the pet and progress stay on the Mac.
With one, the pet (look, name, outfits, points and unlocks), the study streaks and the Party identity follow the user to their other Macs.
Calendar data, activity details, AI chats and settings never sync.

The app keeps one versioned JSON document per user (`SyncDocument` in `Sources/TabbiKitCore/Sync`).
Merges never lose progress: points are a per-Mac tally, unlocks and study days are unions, and the longest streak is a maximum.
The pet's look and name are last-writer-wins by timestamp.
The backend stores the document as is, with a revision number (`GET` and `PUT /v1/sync` in [study/backend-api.md](study/backend-api.md)).
Sign in goes through `POST /v1/auth/apple`, which verifies Apple's identity token and links the Mac's Party identity to the account.
Builds without the native Sign in with Apple entitlement (the Developer ID build, dev and ad-hoc builds) use the web flow instead: Apple's sign-in page posts to the Worker, which hands the app a one-time code through a `tabbi://auth/apple` link, and the app exchanges it at `POST /v1/auth/apple/web/token` for the same result ([study/backend-api.md](study/backend-api.md) has the details).
Delete Account in Settings > General deletes everything the server holds for the user and revokes the Apple grant.
[backend/PRIVACY.md](../backend/PRIVACY.md) lists exactly what is stored.

## What the maintainer does outside the code

These steps need the Apple Developer account and the Cloudflare account, so they cannot live in the code.
The Apple team is an Individual account with Team ID `B9VRALHV8S`, and the app's bundle id is `dev.tabbi.Tabbi`.
Never commit a provisioning profile, the `.p8` key or any secret.

### 1. Enable Sign in with Apple on the App ID

1. Open [Certificates, Identifiers & Profiles > Identifiers](https://developer.apple.com/account/resources/identifiers/list).
2. Open the App ID `dev.tabbi.Tabbi`, or register it (App IDs > App, explicit Bundle ID `dev.tabbi.Tabbi`) if it is not there yet.
3. Under Capabilities, turn on Sign in with Apple and keep "Enable as a primary App ID".
4. Save.

### 2. No Developer ID provisioning profile

Apple's Developer ID provisioning profiles do not grant `com.apple.developer.applesignin` (checked twice, even with a regenerated profile), so the direct download cannot use the native Sign in with Apple sheet.
It signs in on the web instead (step 4), which needs no entitlement and no profile.
`scripts/release.sh` signs with `packaging/Tabbi.entitlements` and embeds no profile.
The old profile is kept, unused, as `packaging/Tabbi-DeveloperID-unused.provisionprofile` (git ignores it): do not embed it, since macOS refuses to launch an app whose entitlements its profile does not cover.
Ad-hoc builds (`--adhoc`, `scripts/bundle.sh`, `scripts/run.sh`) use the web flow too.
Only the App Store edition (`scripts/release-appstore.sh`, [appstore.md](appstore.md)) carries the entitlement and shows Apple's native sheet.

The app picks the flow by itself: with the entitlement in its signature it uses the native sheet, otherwise the web page.
Both reach the same account, because the Services ID is grouped with the App ID.

### 3. Create the Sign in with Apple key

The backend uses this key to exchange the authorization code for a refresh token, and to revoke that token on Delete Account.

1. Open [Keys](https://developer.apple.com/account/resources/authkeys/list) and click +.
2. Name it "Tabbi Sign in with Apple", turn on Sign in with Apple, click Configure and choose the primary App ID `dev.tabbi.Tabbi`.
3. Register it and download `AuthKey_<KeyID>.p8`.
   Apple lets you download it only once, so keep it in a password manager.
4. Note the Key ID that the key's page shows.

### 4. Create the Services ID for web sign-in

The web flow signs in as a Services ID, `dev.tabbi.Tabbi.signin`, grouped with the App ID so Apple gives the user the same id in both flows (one account, whichever build they use).

1. Open [Identifiers](https://developer.apple.com/account/resources/identifiers/list), click +, choose Services IDs and continue.
2. Description "Tabbi web sign-in", identifier `dev.tabbi.Tabbi.signin`. Register it.
3. Open the new Services ID, turn on Sign in with Apple and click Configure.
4. Primary App ID: `dev.tabbi.Tabbi`.
5. Domains and Subdomains: `tabbi-friends.drosophil-anki-friends-backend.workers.dev`.
6. Return URLs: `https://tabbi-friends.drosophil-anki-friends-backend.workers.dev/v1/auth/apple/web/callback` (exactly, with no trailing slash).
7. Click Next, Done, Continue and Save.

The key from step 3 signs the client secrets for the Services ID too, so it needs no key of its own.
The Worker reads the identifier from the variable `APPLE_SERVICES_ID` in `backend/wrangler.toml`, which deploys with the Worker.
A staging Worker has a different host, so to try the web flow there, add its domain and return URL to the same Services ID.

### 5. Set the Worker secrets

In `backend/`, run each command and paste the value when wrangler asks for it:

```sh
npx wrangler secret put APPLE_TEAM_ID       # B9VRALHV8S
npx wrangler secret put APPLE_KEY_ID        # the Key ID from step 3
npx wrangler secret put APPLE_PRIVATE_KEY   # the whole AuthKey_<KeyID>.p8 file, pasted as is
```

Without these secrets, sign-in still works, but the backend skips the code exchange and cannot revoke the Apple grant on Delete Account (it logs both).

### 6. Deploy the backend

In `backend/`, run `npm test` and `npm run typecheck`, then `npx wrangler deploy`.
The first deploy after this change upgrades the database by itself (schema step 2 adds the Apple account, device token and sync tables, and step 11 the pending web sign-ins).

### 7. Ship the app

Run `scripts/release.sh` and publish the release as usual ([install.md](install.md)); it needs nothing extra for sign-in.
Deploy the backend (step 6) first, since the app's web sign-in posts to its callback.
To check a release, open Settings > General, click Sign in with Apple, and sign in on Apple's page: the Account row should show the account.
