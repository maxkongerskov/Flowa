# Flowa — One-Pass Setup

The auto-paste needs **Accessibility permission**, and macOS's TCC system ties that grant to the app's **code signature**. Right now `Flowa.xcodeproj` is set to `CODE_SIGN_STYLE = Automatic` with **no Development Team** — Xcode is ad-hoc signing each build, which produces a different signature every time and silently invalidates the grant. The Settings toggle stays on, but `AXIsProcessTrusted()` returns false. That's why nothing was sticking.

Do these steps **once** in order. After that, dictation just works.

## 1. Sign Flowa with a stable identity

This is the actual fix. Without it the rest is wasted effort.

1. Open `Flowa.xcodeproj`.
2. Select the **Flowa** target in the file navigator.
3. Click the **Signing & Capabilities** tab.
4. Tick **Automatically manage signing**.
5. Pick a **Team**:
   - If you have a paid Apple Developer Program account, use that team.
   - Otherwise sign in to Xcode → Settings → Accounts with your Apple ID and pick the resulting **(Personal Team)**. Free, works.
6. The Signing Certificate row should now read **Apple Development: <your email>**, not "Sign to Run Locally".

That single change makes every future rebuild use the same certificate, so TCC sees it as the same app.

## 2. Wipe the stale TCC state

Run in Terminal — this clears whatever broken grants are cached:

```bash
tccutil reset Accessibility com.maxkongerskov.Flowa
tccutil reset ListenEvent com.maxkongerskov.Flowa
tccutil reset Microphone com.maxkongerskov.Flowa
killall Flowa 2>/dev/null
```

## 3. Build and put the app somewhere stable

The default Xcode build output path lives in `DerivedData` and can change between Xcode versions. Putting the app in `/Applications` (or any fixed location) keeps TCC happy.

1. In Xcode, press ⌘B to build.
2. Product menu → **Show Build Folder in Finder**.
3. Navigate to `Build/Products/Debug/Flowa.app`.
4. Drag it to **/Applications/**.
5. In Terminal, strip the quarantine flag (otherwise first-launch can confuse TCC):
   ```bash
   xattr -dr com.apple.quarantine /Applications/Flowa.app
   ```

## 4. First launch + grant permissions

1. Double-click **/Applications/Flowa.app** (not Xcode — the launch path matters for TCC).
2. macOS will prompt for each permission as Flowa hits it. Accept and toggle Flowa **on** in:
   - **Microphone** (for audio capture)
   - **Input Monitoring** (for the Fn key tap)
   - **Accessibility** (for the auto-paste Cmd+V synthesis)
3. Quit Flowa fully (⌘Q).
4. Relaunch /Applications/Flowa.app once more. Permissions only take effect for a new process after granting.

## 5. Verify

Hold Fn anywhere — Notes, Chrome, anything — and speak. The transcript should auto-paste into that app. If Accessibility is still off for any reason, the text will be on your clipboard for manual ⌘V.

## Ongoing development workflow

Once the team is set in step 1, the signature is stable across rebuilds and **TCC grants survive**. So the day-to-day loop is:

1. Edit code in Xcode.
2. ⌘B to build.
3. Quit /Applications/Flowa.app (⌘Q on Flowa, or `killall Flowa` in Terminal).
4. Copy the fresh build over `/Applications/Flowa.app`:
   ```bash
   cp -R ~/Library/Developer/Xcode/DerivedData/Flowa-*/Build/Products/Debug/Flowa.app /Applications/
   ```
5. Relaunch /Applications/Flowa.app.

If you want to debug from Xcode after the permissions are granted to the `/Applications` copy, use **Product → Perform Action → Run Without Building** — this launches the existing granted binary instead of re-signing a new one.

## Why not just run from Xcode?

Xcode launches the app from `DerivedData/.../Debug/Flowa.app`. Every clean build re-creates that bundle. With ad-hoc signing (no Team), the signature changes every time and TCC treats it as a new app. Even with a Team set, debugger-attached launches sometimes confuse TCC. The `/Applications` path + stable Team combination is the path of least resistance.
