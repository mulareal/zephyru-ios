# AGENTS.md — Handoff for the next agent

ZephyrU ports Cemu (Wii U) to iOS arm64. First target: The Legend of Zelda: The Wind Waker HD
on iPhone 17 Pro (A19 Pro, iOS 26). Read `docs/IOS_PORT_STATUS.md`,
`docs/IOS_PORT_RESEARCH.md` and `docs/IOS_DEVICE_BRINGUP.md` before changing anything; they contain
the full, sourced picture.

## Verified state (do not overclaim)

- `ZephyrU.app` **builds and links for `arm64-apple-ios26.0`** in CI
  (Xcode 26.6 / iPhoneOS 26.5 SDK). Evidence: CI run 34703439905, binary `Mach-O 64-bit arm64`.
- **M0 (launch) and M1 (core init) are verified on hardware** (iPhone 17 Pro, iOS 27.0 `24A5430a`,
  2026-09-12). Evidence: CI artifact run 34714878411 re-signed/installed via `devicectl`, UI + JIT
  row + background/foreground verified, `log.txt` contains
  `ZephyrU: core initialized (JIT: no)` and `mlc01`/`settings.xml` are created. M2–M13 are **not**
  verified; M2 needs a user-imported title.
- The CI artifact is **unsigned**; installing needs a development profile and the workflow in
  `docs/IOS_DEVICE_BRINGUP.md` (free-team profiles do not grant the
  `increased-memory-limit`/`extended-virtual-addressing` entitlements).
- JIT is the gating risk for performance: iOS 26 + TXM needs a debugger-attached development build
  (StikDebug-class); without it the app auto-selects `CPUMode::SinglecoreInterpreter` (slow).

## Repository model (important)

The GitHub repo is a **patch + overlay**, not a Cemu fork:

- `patches/0001-zephyru-cemu-core.patch` — minimal diff against upstream Cemu
  (`3310f3b8b184d64a62b89fd59088c799432badf5`)
- `ios/` — platform layer + UIKit app, copied into the Cemu tree at build time
- `scripts/apply_port.sh` — clones pinned Cemu, applies patch, overlays `ios/`, inits submodules
- CI: `.github/workflows/ios.yml` (macos-26, vcpkg `arm64-ios`, artifact `ZephyrU-app-N`)

Local iteration workflow (the `cemu/` directory is a git clone of upstream and is gitignored):

```bash
# edit files under cemu/ (core patch) and/or cemu/ios/ (overlay)
git -C cemu add -A
git -C cemu diff --cached --binary --output="$PWD/patches/0001-zephyru-cemu-core.patch" -- ':!ios'
rm -rf ios && cp -R cemu/ios ios
git add -A && git commit -m "..." && git push        # push triggers the iOS CI build
```

Always use `--output` for the patch (PowerShell redirection writes UTF-16 and breaks `git apply`).

## Next tasks, in priority order

1. **Title scan + load the game (issues #2/#3, M2–M4).** Import a user-provided `.wua`/`.rpx` into
   `Documents/games`, verify `CafeTitleList` metadata, then `PrepareForegroundTitle` and first
   PowerPC execution (fiber scheduler). M0/M1 are done (see above); the device loop is in
   `docs/IOS_DEVICE_BRINGUP.md`.
2. **JIT enablement (issue #7/#18).** Attempt a debugger-attached session
   (`devicectl --start-stopped` + LLDB device attach) so the AArch64 recompiler can allocate
   executable memory; document the result.
3. **First frames (issue #4, M5–M6)** through the Metal path, then gameplay (issue #5), audio
   (issue #6), performance baseline (issues #7–#8), MetalFX (issues #9–#11).
4. Keep `docs/IOS_PORT_STATUS.md` current and attach evidence to the matching issue.

Full backlog: https://github.com/mulareal/zephyru-ios/issues — board:
https://github.com/users/mulareal/projects/6

## Architecture seams (where iOS code plugs in)

- `ios/platform/WindowSystemIOS.mm` — implements `src/gui/interface/WindowSystem.h` (wx is not built)
- `ios/platform/MetalLayerIOS.mm` — `CreateMetalLayer()` returns the UIView-backed `CAMetalLayer`
- `ios/platform/IOSPlatform.mm` — JIT probe (`vm_region_64`), error dialogs, notifications
- `ios/platform/FiberIOS.cpp` + `ios/third_party/libucontext/` — iOS has no working `ucontext`
  (`ENOTSUP` stubs). Do not switch back to `FiberUnix.cpp`; the vendored libucontext is the fix.
- `ios/platform/AudioUnitAPI.mm` — RemoteIO backend compiled into `CemuAudio`
- `ios/platform/GameControllerProvider.mm` — provider compiled into `CemuInput`; default mapping is
  registered for `InputAPI::IOSController` in `VPADController.cpp` / `ProController.cpp`
- `ios/platform/CemuIOSBridge.mm` — embedding API for the UIKit app (init, load, start, telemetry);
  also defines `g_isGPUInitFinished` (normally in the excluded desktop `main.cpp`)

## Traps learned the hard way

- Any new Darwin `#if BOOST_OS_MACOS` in core code must be `|| defined(CEMU_IOS)`; Boost sets
  neither `BOOST_OS_MACOS` nor `BOOST_OS_UNIX` on iOS.
- ObjC++ must live in `.mm` files with `-fobjc-arc` per file (see CMake patches).
- Platform sources include `Common/precompiled.h` explicitly; C sources from libucontext set
  `SKIP_PRECOMPILE_HEADERS`.
- The app must link `CemuUtil` and `CemuResource` explicitly (desktop gets them via `CemuBin`/
  `CemuWxGui`).
- Core headers include the overlay as `"ios/platform/..."`; the root include dir is added globally
  under `CEMU_IOS`.
- Do not use jailbreak exploits or private APIs. JIT only via development signing + debugger
  attach (documented in `docs/IOS_PORT_RESEARCH.md` §3.4/§3.5).
- **LTO duplicates vague-linkage symbols on iOS.** ThinLTO internalized inline variables and
  function-local statics per static library (`ActiveSettings::s_config_path`,
  `GetConfigHandle()::config`), so the overlay and core silently used different copies. LTO is
  disabled for `CEMU_IOS`; if a global/static suddenly reads as default-initialized, check `nm` for
  a second local (`b`) copy.
- **No executable-memory allocation in static initializers.** Global xbyak `CodeGenerator`s
  (`AArch64GenContext_t`) abort before `main` when JIT is unavailable; construct code generators
  lazily (see `PPCRecompilerAArch64Gen_generateRecompilerInterfaceFunctions`).
- Never commit game files, keys, or saves. The user supplies their own title.

## Definition of done for any work

Evidence or it did not happen: CI run URL, device log, screenshot, or measurement (frame times,
speed %, thermal state). Report FPS strictly as simulation rate / rendered FPS / generated FPS /
presented display FPS — never mix them.
