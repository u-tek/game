# Building the iOS app (IPA)

The game is a Godot 4.5.1 project. iOS builds need Apple's Xcode, which only runs on macOS,
so the IPA is built on GitHub's macOS runners by the **iOS build** workflow
(`.github/workflows/ios.yml`).

## How a build works

1. Godot (macOS editor, headless) imports the project and runs the unit tests.
2. Godot exports an **Xcode project** using the iOS preset in `export_presets.cfg`
   (`export_project_only=true`, dummy team ID).
3. `xcodebuild` compiles it **without code signing**.
4. The `.app` is zipped as `Payload/HaloAndHorn.app` → `HaloAndHorn.ipa` and uploaded as the
   run's artifact `HaloAndHorn-ipa` (kept 14 days).

## Running it

GitHub Actions must be able to start jobs on the repo. On this account they currently fail
instantly (no logs), which usually means a billing or spending-limit block on private repos.
Public repos get macOS minutes free. Then:

- GitHub → **Actions** → **iOS build** → **Run workflow**, or ask Claude to trigger it.
- A build takes about 10–20 minutes (the first run downloads Godot and templates, ~1 GB; later
  runs use the cache).
- Download the artifact from the run page (it's a .zip containing `HaloAndHorn.ipa`).

## Sideloading

The IPA is unsigned; your sideloading tool signs it with your Apple ID.

- **Sideloadly** (Windows/Mac): connect the iPhone by cable, drop in the IPA, enter your Apple ID,
  press Start.
- **AltStore / SideStore**: open the IPA from Files with AltStore ("My Apps" → +).
- On the iPhone: enable **Settings → Privacy & Security → Developer Mode** (iOS 16+), then trust
  the profile under **Settings → General → VPN & Device Management**.
- With a free Apple ID, sideloaded apps expire after 7 days (re-sign to refresh), and you can
  have 3 at a time.

## Save data

The save lives in the app's sandbox (`user://save.json`). Reinstalling over the top keeps it;
deleting the app deletes it. Settings → Reset save starts over.

## Known limitations

- No App Store signing/provisioning yet (needs an Apple Developer account, $99/year).
- App icon and launch screen come from Godot's export using `icon.svg` and the preset's
  background color.
