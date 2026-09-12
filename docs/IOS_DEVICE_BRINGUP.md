# ZephyrU — iOS device bring-up (sign, install, launch, logs)

How to get a CI-built `ZephyrU.app` onto a physical iPhone and read its logs. This is the loop used
for M0/M1 (see `docs/IOS_PORT_STATUS.md`). All commands run on macOS with Xcode installed.

## 0. Prerequisites

- iPhone paired with this Mac, **Developer Mode enabled**, unlocked while installing.
- An Apple Development identity in the keychain:
  `security find-identity -v -p codesigning`
- The CI artifact of a green `iOS Build` run (Actions → `ZephyrU-app-<run_number>`), or a local
  Release build.
- A valid provisioning profile for `com.zephyru.emulator` that includes the device UDID and
  `get-task-allow` (section 2). Free-Apple-ID profiles expire after **7 days**.

Check the device state first; `available (paired)` is not enough, installs need `connected`:

```bash
xcrun devicectl list devices
```

If the phone shows `unavailable`, wake and unlock it, then retry.

## 1. Get the app

```bash
gh run download <run-id> --repo mulareal/zephyru-ios -n ZephyrU-app-<run_number> -D artifacts
unzip -q artifacts/ZephyrU.app.zip -d build
```

Using a local CMake build instead: `build-ios/ios/Release-iphoneos/ZephyrU.app`.

## 2. Provisioning profile (needed once per 7 days with a free team)

Xcode's automatic signing creates and refreshes the profile. Any project with the same bundle ID
works; a minimal stub project is enough:

- iOS App target, `PRODUCT_BUNDLE_IDENTIFIER = com.zephyru.emulator`,
  `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = <TEAM_ID>`.
- Build it once:

```bash
xcodebuild -project SigningStub.xcodeproj -target SigningStub \
  -configuration Debug -sdk iphoneos -allowProvisioningUpdates build
```

Xcode registers the App ID and the connected device with the team and writes the profile to
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`.

Extract the profile's entitlements (they are the only ones the profile allows; a free team does
**not** grant `com.apple.developer.kernel.increased-memory-limit` or
`...extended-virtual-addressing`, and the app degrades gracefully without them):

```bash
PROFILE=~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision
security cms -D -i "$PROFILE" > /tmp/profile.plist
plutil -extract Entitlements xml1 -o /tmp/profile-entitlements.plist /tmp/profile.plist
# check UUID, ExpirationDate and ProvisionedDevices
plutil -p /tmp/profile.plist | grep -E 'UUID|Name|ExpirationDate'
plutil -p /tmp/profile.plist | grep -A2 ProvisionedDevices
```

## 3. Re-sign the CI artifact

The CI artifact is unsigned. Embed the profile and sign with the keychain identity:

```bash
cp "$PROFILE" build/ZephyrU.app/embedded.mobileprovision
codesign --force --sign "Apple Development: <name> (<cert-id>)" \
  --entitlements /tmp/profile-entitlements.plist \
  --generate-entitlement-der build/ZephyrU.app
codesign --verify --strict build/ZephyrU.app
```

## 4. Install and launch

```bash
xcrun devicectl device install app --device <DEVICE_UDID> build/ZephyrU.app
xcrun devicectl device process launch --device <DEVICE_UDID> \
  --console --terminate-existing com.zephyru.emulator
```

- Free teams can have at most **three** development-signed apps installed per device. The error
  says `This device has reached the maximum number of installed apps using a free developer
  profile` and lists the apps; uninstall one with
  `xcrun devicectl device uninstall app --device <DEVICE_UDID> <bundle-id>`.
- `--console` forwards the app's `stdout`/`stderr`, including `NSLog`, until the app exits.
- `--start-stopped` launches suspended and waits for a debugger (JIT path).

## 5. Logs, files and crash reports

```bash
# Cemu's own log (written by cemuLog_createLogFile during core init)
xcrun devicectl device copy from --device <DEVICE_UDID> \
  --domain-type appDataContainer --domain-identifier com.zephyru.emulator \
  --source "Library/Application Support/log.txt" --destination log.txt

# list the app container (mlc01, settings.xml, Documents/games, ...)
xcrun devicectl device info files --device <DEVICE_UDID> \
  --domain-type appDataContainer --domain-identifier com.zephyru.emulator

# crash reports (also includes older ones)
xcrun devicectl device copy from --device <DEVICE_UDID> \
  --domain-type systemCrashLogs --source . --destination crashes
```

`Library/Application Support` is the user data path; `mlc01`, `settings.xml`, `log.txt` and
`title_list_cache.xml` live there. Game files are scanned in `Documents/games`.

## 6. JIT

Without a debugger the kernel strips execute permission, the probe reports
`AArch64 recompiler: unavailable`, and the app selects `CPUMode::SinglecoreInterpreter` (visible in
the Environment row and in `log.txt` as `core initialized (JIT: no)`). The recompiler requires a
development-signed build attached to a debugger (StikDebug-class on iOS 26/27, see
`docs/IOS_PORT_RESEARCH.md` §3.4/§3.5). `devicectl ... --start-stopped` plus an LLDB device attach
is the intended local workflow; plain `lldb device process attach` was not yet successful with
Xcode 26.5 and needs another attempt.

## 7. Common problems

| Symptom | Cause / fix |
|---|---|
| `CoreDeviceService was unable to locate a device` (error 1011) | Phone asleep/locked — wake and unlock, check `devicectl list devices` shows `connected` |
| `maximum number of installed apps using a free developer profile` | Free team limit of 3 installed apps; uninstall one |
| Install fails and the error mentions the bundle ID | Profile expired (7 days) or device UDID missing from the profile; redo section 2 |
| App aborts before the UI with a C++/xbyak message | Executable-memory allocation during static init; check the code path only constructs code generators lazily |
| Paths look relative (`controllerProfiles`, missing `mlc01`) | Vague-linkage symbols got duplicated at link time (LTO); ensure `CEMU_IOS` disables IPO and `nm` shows a single copy |
