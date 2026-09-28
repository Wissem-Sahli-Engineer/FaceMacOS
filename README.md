# FaceMacOS

Face ID–style face recognition for any Mac with a camera. Close the lid, open it, look at the camera and blink: FaceMacOS recognizes you and unlocks your Mac, with a Face ID animation in the notch.

- **Automatic Mac unlock**: scanning starts as soon as you open the lid or wake the screen. No clicks.
- **Notch animations**: scanning, success and failure animations at the top of the screen, visible on the lock screen too.
- **Face vault**: a private note that opens only with your face (⌥⌘F).
- **Gesture commands**: after recognizing you, blink twice or look left/right/up/down to open apps, websites and Shortcuts, or lock the screen (⌥⌘G).
- **Your color**: choose the accent color of the animations and interface.
- **Private**: everything runs on your Mac. No images are saved, and face data and your password stay in your Keychain.

## Requirements

- macOS 13 Ventura or later (Apple silicon or Intel)
- A built-in or external camera
- For automatic unlock: your Mac login password and Accessibility permission (see below)

## Install

1. Download `FaceMacOS.dmg` from the website, or from [`website/downloads`](website/downloads/FaceMacOS.dmg) in this repository.
2. Open the DMG and drag **FaceMacOS** onto the **Applications** folder.
3. Eject the DMG, then open FaceMacOS from Applications.

If macOS says the app "can't be opened because Apple cannot check it for malicious software" (builds without Apple notarization):
open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to FaceMacOS. You only need to do this once.
Or run once in Terminal: `xattr -dr com.apple.quarantine /Applications/FaceMacOS.app`

FaceMacOS lives in the menu bar (the Face ID icon). It opens at login automatically and restarts itself if it ever stops unexpectedly.

## Set up

The main window opens on first launch. Open it any time from the menu bar icon → **Open FaceMacOS…**

1. **Set up Face ID**: click **Set Up Face ID**, allow camera access, and slowly move your head in a circle until the ring is complete (about 15 seconds). Blink once when asked.
2. **Try it**: press **⌥⌘F**. The animation appears in the notch; blink to confirm.

### Unlock your Mac with your face

Open **Mac Unlock** in the sidebar:

1. Turn on **Unlock the lock screen with Face ID**.
2. **Save your login password**. It's checked against your account, then stored in your Keychain. FaceMacOS types it for you after it recognizes you.
3. **Grant Accessibility permission**: click **Open Settings…** and turn on FaceMacOS (needed to type the password). If it's already on but not detected, remove it with **−** and add it again.
4. If macOS asks **"FaceMacOS wants to use your confidential information stored in your keychain"**, enter your password and click **Always Allow**.

Then close the lid (or lock with ⌃⌘Q), open it and look at the camera. When the animation appears, blink.

## Settings

- **Open at login and keep running**: on by default. If macOS shows a *Background Items Added* notification, leave FaceMacOS allowed in **System Settings → General → Login Items**.
- **Accent color**: pick a preset or any custom color for the animations and interface.
- **Require a blink**: liveness check for the vault and tests (always on for Mac unlock).
- **Show icon in Dock**: turn off to keep FaceMacOS only in the menu bar.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Mac doesn't unlock | Check all items in **Mac Unlock** are green. Open FaceMacOS once after every update so macOS can ask for Keychain access while you can answer. |
| "Face Not Recognized" often | Improve lighting (face lit from the front), then **Set Up Again**. Use **Live Camera** to check image quality. |
| Accessibility is on but not detected | In System Settings → Privacy & Security → Accessibility, remove FaceMacOS with **−**, add it again with **+**. |
| No animation on the lock screen | Make sure you're on the latest version and FaceMacOS is running (menu bar icon). |
| App doesn't start at login | System Settings → General → Login Items: allow FaceMacOS. Or open the app once; it re-registers itself. |

Logs for bug reports (run in Terminal):

```sh
log show --last 30m --predicate 'subsystem == "com.facemacos.app"'
```

## Uninstall

1. Open FaceMacOS → **Settings → Delete All Data…** (removes face data, vault note and saved password from your Keychain).
2. Turn off **Open at login and keep running**, then choose **Quit FaceMacOS** from the menu bar icon.
3. Drag FaceMacOS from Applications to the Trash.

## Security

FaceMacOS makes unlocking convenient, but a regular webcam is **not as secure as Apple's Face ID**, which uses a 3D depth camera. FaceMacOS requires a blink and checks for motion so a printed photo can't unlock your Mac, but a determined attacker with a video of you might. Don't use automatic unlock on a Mac that holds sensitive data. Your login password is stored in your login Keychain and is only typed into the lock screen after your face is verified.

Automatic unlock works on the lock screen and screen saver, not at startup, after logging out, or on the FileVault login screen (macOS requires your password there).

---

## For developers

### Build from source

Requires Xcode 15 or later (Swift 6 toolchain).

```sh
scripts/setup_signing.sh        # once: creates a local code-signing identity so permissions survive rebuilds
scripts/build.sh debug --run    # builds build/FaceMacOS.app and launches it
```

The face model (`Models/FaceEmbedding.mlpackage`, FaceNet trained on VGGFace2) is in the repo. To regenerate it, see `scripts/convert_facenet.py`.

Local builds use a self-signed certificate. Because it has no Apple Team ID, macOS asks for Keychain access again after each rebuild, and launch at login re-registers when you open the rebuilt app.

### Release a new version (users update in-app)

FaceMacOS updates itself with [Sparkle](https://sparkle-project.org): about once a day, while online, it checks `https://facemacos.onrender.com/appcast.xml`, and offers to install newer versions. Users can also choose **Check for Updates…** in the menu bar or in Settings.

1. In `Resources/Info.plist`, raise `CFBundleShortVersionString` (e.g. `1.2.0`) and **`CFBundleVersion`** (e.g. `3`). Sparkle compares `CFBundleVersion`, so it must go up every release; `release.sh` refuses to run otherwise.
2. Run, with a short note users will see in the update window:
   ```sh
   NOTES="Faster unlock and a new gesture." scripts/release.sh
   ```
   This builds a universal (Apple silicon + Intel) app and `build/FaceMacOS.dmg`, copies it to `website/downloads/FaceMacOS.dmg` (served by the Download buttons), signs it with your update key, and writes `website/appcast.xml`.
3. Commit and push `website/downloads/FaceMacOS.dmg` and `website/appcast.xml`. Render redeploys, and installed copies pick up the update.

Updates installed through Sparkle don't carry the download quarantine flag, so users only see the "could not verify … malware" warning on their very first install.

#### Back up your two release keys

An update is only installed if it's signed with **both** keys below. If you lose either one, installed copies can never be updated again and every user has to reinstall by hand. Keep backups somewhere safe outside this Mac (a password manager, an encrypted USB drive), and never commit them.

- **Sparkle update key** (created with `generate_keys`, stored in your login Keychain):
  ```sh
  .build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/sparkle-private-key.txt   # export; move it somewhere safe
  .build/artifacts/sparkle/Sparkle/bin/generate_keys -f sparkle-private-key.txt             # import on a new Mac
  ```
  Its public half is `SUPublicEDKey` in `Resources/Info.plist`; don't change it.
- **Code-signing certificate** "FaceMacOS Local Signing" (created by `scripts/setup_signing.sh`): in **Keychain Access → login → My Certificates**, right-click it → **Export…** as a `.p12` with a password. On a new Mac, double-click the `.p12` to import it. Don't run `setup_signing.sh` again on a new Mac; it would create a different certificate.

If you later switch to an Apple Developer ID, ship one release signed with the Developer ID through the normal update so everyone moves over. The Sparkle key stays the same.

Optionally also publish it on GitHub: **Releases → Draft a new release**, tag `v1.0.0`, attach `build/FaceMacOS.dmg` without renaming it. Then `releases/latest/download/FaceMacOS.dmg` always serves the newest release too. The window layout lives in `scripts/dmg_settings.py` and its background in `scripts/make_dmg_background.swift`.

For a DMG that opens without Gatekeeper warnings, sign with a Developer ID and notarize (needs an Apple Developer Program membership):

```sh
xcrun notarytool store-credentials facemacos --apple-id <you@example.com> --team-id <TEAMID>   # once
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=facemacos scripts/release.sh
```

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` before each release.

### Website

`website/` is the product site: a static page (HTML, CSS, JS) animated with GSAP ScrollTrigger and Lenis smooth scrolling, no build step. Preview it locally:

```sh
cd website && python3 -m http.server 8765   # then open http://localhost:8765
```

**Deploy it on Render (free):**

1. Push this repo to GitHub (already done).
2. On [render.com](https://render.com), **New → Blueprint**, pick this repo. Render reads `render.yaml` at the repo root and creates a free static site serving `website/`, no build step.
   - No Render account yet, or you'd rather click through it by hand: **New → Static Site**, pick the repo, set **Root Directory** to `website`, leave **Build Command** empty, set **Publish Directory** to `.`.
3. Render gives you a free `https://facemacos.onrender.com`-style URL immediately. No domain purchase needed.
4. Every push to `main` redeploys automatically.

Alternative: GitHub Pages — repository **Settings → Pages**, deploy from the `main` branch and the `/website` folder.

**Getting the DMG to users:** the Download buttons link to `downloads/FaceMacOS.dmg`, a file inside the `website` folder — so it's served automatically by whichever host you pick, no extra setup. When you ship a new version, `scripts/release.sh` overwrites that file; commit it so the live site updates. Users always get the current file at the same URL, so there's no separate "update" step for them beyond downloading the DMG again — FaceMacOS itself has no auto-updater.

Two things worth knowing:

- Each release adds another ~22 MB to `website/downloads/FaceMacOS.dmg`, and since it's committed, the repo's history grows by that much every time (git never shrinks old blobs on its own). Fine for a while; if it becomes a problem, move the DMG to [Git LFS](https://git-lfs.com) or to GitHub Releases (`releases/latest/download/FaceMacOS.dmg`) and point the Download buttons there instead.
- If you'd like people to see a changelog or pick an older version, publish a GitHub Release too (see below) and link to it from the site.

### Project layout

| Folder | Contents |
| --- | --- |
| `App/` | App entry, menu bar, hotkeys, single-instance handling |
| `Auth/` | Face authentication, enrollment, and presence detection |
| `Camera/`, `Vision/` | Camera capture and face analysis (landmarks, quality, crops) |
| `Recognition/`, `Liveness/` | Face embeddings, matching, blink/motion liveness, gestures |
| `LockScreen/` | Lock-screen unlock, permissions, password typing |
| `Notch/` | Notch animations (shown above the lock screen via a SkyLight space) |
| `UI/`, `Settings/` | Main window, settings, accent color |
| `Resources/LaunchAgents/` | Login agent that starts FaceMacOS at login and restarts it if it stops |
