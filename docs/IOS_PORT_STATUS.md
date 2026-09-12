# ZephyrU — iOS Port Status

Living document. Last updated 2026-09-12.
Upstream baseline: `cemu-project/Cemu` @ `3310f3b8b184d64a62b89fd59088c799432badf5`.

Legend: **DONE** implemented, **SCAFFOLDED** code written but not yet compiled on device,
**CI** being validated by the macOS CI build, **BLOCKED** needs an external input,
**TODO** not started.

## Milestones

| ID | Goal | Status | Evidence / Blockers |
|---|---|---|---|
| M0 | iOS application launches | SCAFFOLDED | `ios/app` UIKit app + `ZephyrU` target in `ios/CMakeLists.txt`; CI build pending |
| M1 | Cemu core initializes | SCAFFOLDED | `CemuIOSBridge::initializeCoreWithError` ports `CemuCommonInit`/`CemuApp::OnInit` path setup, MLC creation, audio/input/graphic-pack init |
| M2 | Game metadata readable | SCAFFOLDED | `CafeTitleList` initialized with Documents/games scan path; `.rpx` standalone path supported directly |
| M3 | Wind Waker HD executable loads | TODO | `PrepareForegroundTitle`/`…FromStandaloneRPX` wired; needs a compiled build and a user-provided title |
| M4 | First PowerPC code executes | TODO | depends on M3 |
| M5 | First GX2 commands execute | TODO | Metal renderer exists upstream; iOS surface implemented |
| M6 | First visible frame | TODO | depends on M4/M5 |
| M7 | Title screen | TODO | |
| M8 | In-game Outset Island | TODO | |
| M9 | Stable audio | SCAFFOLDED | `AudioUnitAPI` (RemoteIO) implements `IAudioAPI`; not yet tuned on device |
| M10 | Stable 30 FPS / 100% speed | TODO | requires JIT-enabled device or interpreter measurement (expected interpreter-unsuitable; see research §3/§6) |
| M11 | 30-minute stability test | TODO | |
| M12 | 60 Hz interpolated presentation | TODO | MetalFX frame interpolation (iOS 26, A19 = Apple10) planned; research §5 |
| M13 | 120 Hz-class presentation | TODO | 30→120 needs multi-frame interpolation research; 60→120 is API-supported |

## Components

| Component | Status | Blocker | Next action |
|---|---|---|---|
| CMake iOS platform selection (`CEMU_IOS`, iOS target) | SCAFFOLDED | none | CI configure must pass |
| `CemuCafe` core build for `arm64-apple-ios` | CI | long tail of desktop assumptions | iterate CI errors |
| `CemuCommon` (unix platform, MemMapper) | CI | none known | CI |
| PPC IML + AArch64 recompiler | SCAFFOLDED | executable memory (JIT) availability on iOS 26/TXM | validate codegen on device with JIT; interpreter fallback in place |
| PPC interpreter fallback (`CPUMode::SinglecoreInterpreter`) | DONE (upstream) | performance unsuitable for full speed | auto-selected when the JIT probe fails |
| Cooperative fiber scheduler (`util/Fiber`) | DONE (port) | none | `ios/platform/FiberIOS.cpp` + vendored ISC-licensed libucontext AArch64 backend; iOS stubs POSIX ucontext to ENOTSUP (see research §3.2) |
| Metal renderer (GX2→Metal) | SCAFFOLDED | iOS surface integration | CI compile + device test |
| Metal surface (`CreateMetalLayer` for UIView/CAMetalLayer) | SCAFFOLDED | none | CI compile |
| `WindowSystem` iOS implementation | SCAFFOLDED | none | CI compile |
| Audio `AudioUnitAPI` (RemoteIO) | SCAFFOLDED | none | CI compile, then latency tuning |
| Input `GameControllerProvider` | SCAFFOLDED | none | CI compile, then controller test |
| Default controller mapping for `IOSController` | SCAFFOLDED | none | CI compile |
| File import (`UIDocumentPicker` → Documents/games) | SCAFFOLDED | none | device test |
| Save data path (MLC in Application Support) | SCAFFOLDED | crash-consistency hardening | add flush-on-background |
| JIT capability probe + UI status | DONE | none | CI compile |
| MetalFX frame interpolation / upscaling | TODO | needs JIT for full-speed rendering, motion-vector synthesis design | research doc §5 |
| Performance overlay (EMU/DISPLAY/GENERATED FPS, speed %) | SCAFFOLDED | only frame counters for now | extend bridge telemetry with per-stage timings |
| Thermal management | TODO | device access | `ProcessInfo.thermalState` scaling policy |
| 60/120 FPS game-logic experiment | TODO | device access | locate WWHD frame-delta code |
| Regression tests | TODO | none | port upstream unit tests behind `CEMU_IOS` |

## Exact blockers and their attack plan

1. **iOS JIT policy (critical path for performance).** App Store/standard signing forbids
   executable memory; a development-signed app with `get-task-allow` attached to a debugger
   (StikDebug-class on iOS 26/TXM) is required for the AArch64 recompiler. Verified sources in
   `docs/IOS_PORT_RESEARCH.md` §3.4/§3.5. The app detects this at runtime (real mmap+mach probe),
   reports it in the UI, and automatically selects `CPUMode::SinglecoreInterpreter` when
   executable memory is unavailable. No exploit is used.
2. **iOS stubs POSIX ucontext.** Cemu's fiber scheduler would silently fail; replaced with the
   vendored libucontext AArch64 implementation (`ios/third_party/libucontext`), the same approach
   used by UTM/QEMU. See research §3.2.
3. **First full iOS configure/build.** Long tail expected in: boost/unix platform code,
   `Common/unix/platform.cpp`, `ExceptionHandler_posix.cpp`, sockets (`nsysnet`), and
   `CafeSystem` thread naming. CI logs drive fixes; no subsystem is commented out.
4. **vcpkg iOS dependency build time.** Mitigated with a binary cache in CI and an iOS-trimmed
   manifest (`scripts/ios-vcpkg.json`).

## Build evidence log

| Run | Commit | Target | Result |
|---|---|---|---|
| 34695711138 | 27414fe | CemuCommon | FAILED (configure): vcpkg shallow clone missing pinned baseline commit `f0fb3dd`; workflow fixed |
| (pending) | | CemuCommon | re-run after vcpkg fetch fix + `Common/unix/platform.cpp` and `cpu_features.cpp` iOS guards |
