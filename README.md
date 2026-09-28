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

### Release a DMG

```sh
scripts/release.sh
```

Builds a universal (Apple silicon + Intel) app and `build/FaceMacOS.dmg` with the drag-to-Applications window.

It also copies the DMG to `website/downloads/FaceMacOS.dmg`, which the website's Download buttons serve directly. Commit that file with the website so the hosted site offers the new version.

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

To publish it with GitHub Pages: repository **Settings → Pages**, deploy from the `main` branch and the `/website` folder (or copy the folder to any static host).

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
