# ZephyrU â€” iOS Port Status

Living document. Last updated 2026-09-12.
Upstream baseline: `cemu-project/Cemu` @ `3310f3b8b184d64a62b89fd59088c799432badf5`.

Legend: **DONE** verified, **SCAFFOLDED** code written but not yet exercised on device,
**CI** being validated by the macOS CI build, **BLOCKED** needs an external input, **TODO** not started.

## Headline

`ZephyrU.app` **builds for `arm64-apple-ios`** (Xcode 26.6, iPhoneOS 26.5 SDK) in CI: the entire
upstream Cemu core (`CemuCafe`, `CemuCommon`, `CemuComponents`, `CemuConfig`, `CemuInput`,
`CemuAudio`, `CemuUtil`, `CemuResource`, the native Metal renderer and the AArch64 recompiler) plus
the new iOS platform layer compile and link into a real application bundle.
Verified by CI run [34703439905](https://github.com/mulareal/zephyru-ios/actions/runs/34703439905)
("BUILD SUCCEEDED", link line shows every static library and framework, output
`build-ios/ios/Release-iphoneos/ZephyrU.app/ZephyrU`, target `arm64-apple-ios26.0`).

**M0 and M1 are verified on hardware** (2026-09-12): the CI artifact of run
[34714878411](https://github.com/mulareal/zephyru-ios/actions/runs/34714878411) was re-signed with
the development team profile for `com.zephyru.emulator` and installed on the paired iPhone 17 Pro
(`iPhone18,1`, iOS 27.0 `24A5430a`) via `devicectl`. The app launches to the game list, the
Environment row reports `AArch64 recompiler: unavailable` (no debugger attached, interpreter mode),
backgrounding and re-foregrounding keeps the same process alive, and the core initialized:

```
[21:47:55.639] ------- Init Cemu 3310f3b -------
[21:47:55.639] mlc01 path: .../Library/Application Support/mlc01
[21:47:55.672] ZephyrU: core initialized (JIT: no)
[21:47:55.672] ZephyrU: data path .../ZephyrU.app/SharedSupport
[21:47:55.672] ZephyrU: mlc path .../Library/Application Support/mlc01
```

M2 (title metadata) onward still need a user-imported title; the scan path `Documents/games` and
`CafeTitleList` are initialized. See `docs/IOS_DEVICE_BRINGUP.md` for the signing/install loop.

## Milestones

| ID | Goal | Status | Evidence / Blockers |
|---|---|---|---|
| M0 | iOS application launches | **DONE** (device) | CI artifact run 34714878411 re-signed + installed on iPhone 17 Pro (iOS 27.0); UI, JIT-status row, background/foreground verified; process survives Settings foregrounding; see bring-up log below |
| M1 | Cemu core initializes | **DONE** (device) | `log.txt`: `ZephyrU: core initialized (JIT: no)`; `mlc01` (sys/usr titles, save dirs, `language.txt`, `country.txt`, `PlayDiary.dat`), `settings.xml`, `controllerProfiles`, `memorySearcher`, `Documents/games` all created |
| M2 | Game metadata readable | BLOCKED (user input) | First real title imported (`.wux`, Wind Waker HD EU) and listed by the app; `TitleInfo` parse returns `NO_DISC_KEY` (invalid reason 3) because the image is encrypted. `Documents/keys.txt` is copied to the user data path for Cemu's KeyCache; needs the user's own keys or a decrypted dump |
| M3 | Wind Waker HD executable loads | TODO | `PrepareForegroundTitle`/`â€¦FromStandaloneRPX` wired; needs device run |
| M4 | First PowerPC code executes | TODO | depends on M3; fiber scheduler now has a working iOS backend (libucontext) |
| M5 | First GX2 commands execute | TODO | Metal renderer + iOS CAMetalLayer surface compiled |
| M6 | First visible frame | TODO | depends on M4/M5 |
| M7 | Title screen | TODO | |
| M8 | In-game Outset Island | TODO | |
| M9 | Stable audio | SCAFFOLDED | `AudioUnitAPI` (RemoteIO) compiled into CemuAudio; not yet tuned on device |
| M10 | Stable 30 FPS / 100% speed | TODO | requires JIT-enabled device or interpreter measurement (interpreter expected to be too slow; research Â§3/Â§6) |
| M11 | 30-minute stability test | TODO | |
| M12 | 60 Hz interpolated presentation | TODO | MetalFX frame interpolation (iOS 26, A19 = Apple10) planned; research Â§5 |
| M13 | 120 Hz-class presentation | TODO | 30â†’120 needs multi-frame interpolation research; 60â†’120 is API-supported |

## Components

| Component | Status | Blocker | Next action |
|---|---|---|---|
| CMake iOS platform selection (`CEMU_IOS`, iOS target) | DONE | none | CI configure green |
| `CemuCafe` core build for `arm64-apple-ios` | DONE | none | compiled + linked |
| `CemuCommon` (unix platform) | DONE | none | compiled + linked |
| PPC IML + AArch64 recompiler | DONE (build) | executable memory (JIT) availability on iOS 26/TXM at runtime | validate codegen on device with JIT; interpreter fallback auto-selected |
| Cooperative fiber scheduler (`util/Fiber`) | DONE | none | `ios/platform/FiberIOS.cpp` + vendored ISC-licensed libucontext AArch64 backend; iOS stubs POSIX ucontext to ENOTSUP (research Â§3.2) |
| PPC interpreter fallback (`CPUMode::SinglecoreInterpreter`) | DONE (upstream) | performance unsuitable for full speed | auto-selected when the JIT probe fails |
| Metal renderer (GX2â†’Metal) | DONE (build) | runtime validation | device run |
| Metal surface (`CreateMetalLayer` for UIView/CAMetalLayer) | DONE (build) | none | device run |
| `WindowSystem` iOS implementation | DONE (build) | none | device run |
| Audio `AudioUnitAPI` (RemoteIO) | DONE (build) | none | latency tuning on device |
| Input `GameControllerProvider` | DONE (build) | none | controller test on device |
| Default controller mapping for `IOSController` | DONE (build) | none | verify button mapping on device |
| File import (`UIDocumentPicker` â†’ Documents/games) | DONE (build) | none | device test |
| Save data path (MLC in Application Support) | DONE (device) | crash-consistency hardening | add flush-on-background |
| User key import (`Documents/keys.txt` → user data) | DONE (build) | needs a title that requires keys to verify end to end | user supplies keys.txt |
| JIT capability probe + UI status | DONE (device) | device reports `AArch64 recompiler: unavailable` without debugger, as designed | validate JIT path with debugger attach (StikDebug-class) |
| MetalFX frame interpolation / upscaling | TODO | needs JIT for full-speed rendering, motion-vector synthesis design | research Â§5 |
| Performance overlay (EMU/DISPLAY/GENERATED FPS, speed %) | SCAFFOLDED | only frame counters for now | extend bridge telemetry with per-stage timings |
| Thermal management | TODO | device access | `ProcessInfo.thermalState` scaling policy |
| 60/120 FPS game-logic experiment | TODO | device access | locate WWHD frame-delta code |
| Regression tests | TODO | none | port upstream unit tests behind `CEMU_IOS` |

## Exact blockers and their attack plan

1. **iOS JIT policy (critical path for performance).** App Store/standard signing forbids
   executable memory; a development-signed app with `get-task-allow` attached to a debugger
   (StikDebug-class on iOS 26/TXM) is required for the AArch64 recompiler. Verified sources in
   `docs/IOS_PORT_RESEARCH.md` Â§3.4/Â§3.5. The app detects this at runtime (real mmap+mach probe),
   reports it in the UI, and automatically selects `CPUMode::SinglecoreInterpreter` when
   executable memory is unavailable. No exploit is used.
2. **iOS stubs POSIX ucontext.** Cemu's fiber scheduler would silently fail; replaced with the
   vendored libucontext AArch64 implementation (`ios/third_party/libucontext`), the same approach
   used by UTM/QEMU. See research Â§3.2.
3. **Device validation.** M0â€“M10 require a physical iPhone 17 Pro (and a development signing
   identity able to grant `increased-memory-limit` / `extended-virtual-addressing`). The CI
   artifact `ZephyrU.app.zip` is the input for that step.
4. **vcpkg iOS dependency build time.** Solved with a binary cache; subsequent CI runs restore all
   20 iOS dependencies in about one minute.

## Build evidence log

All runs use GitHub Actions `macos-26` (Xcode 26.6, iPhoneOS 26.5 SDK), target `ZephyrU`,
`CMAKE_SYSTEM_NAME=iOS`, `CMAKE_OSX_ARCHITECTURES=arm64`.

| Run | Result | First error / action taken |
|---|---|---|
| 34695711138 | FAILED configure | vcpkg shallow clone missing pinned baseline â†’ full clone |
| 34695778566 | FAILED configure | vcpkg versioned ports need full history â†’ full clone |
| 34695830761 | FAILED configure | ZArchive `install()` needs BUNDLE DESTINATION on iOS â†’ default non-bundle |
| 34696332844 | FAILED configure | relative `../ios/...` source paths â†’ absolute `${CMAKE_SOURCE_DIR}` |
| 34696844197 | FAILED build | `ios/platform/GameControllerProvider.h` not found from core TUs â†’ global include dir |
| 34697067486 | FAILED build | `weakSelf` scope, `uint32` in app sources â†’ fixed |
| 34697250883 | FAILED build | ObjC++ code in `.cpp` files â†’ renamed to `.mm`, ARC per-file |
| 34697619913 | FAILED build | `mach_vm.h` unsupported on iOS â†’ `vm_region_64` probe |
| 34697963195 | FAILED build | `std::string` â†’ `const char*` in error shim |
| 34698337905 | FAILED build | `CrashDump` enum guarded by `BOOST_OS_UNIX` (not set on iOS) â†’ include CEMU_IOS |
| 34698718640 | FAILED build | `system()` unavailable on iOS (macOS debug helper) â†’ guarded |
| 34699141707 | FAILED build | `robin_hood` pulled in transitively via Vulkan on desktop â†’ direct include |
| 34699610712 | FAILED build | `VulkanRendererConst` alias used unguarded in LatteBufferData â†’ `LatteConst::ShaderType` |
| 34700641025 | FAILED build | CoreAudio `AudioUnit` shadowed by `AudioAPI::AudioUnit` enum â†’ `::AudioUnit` |
| 34701137922 | FAILED build | `shared_lock` on `std::mutex` â†’ `std::shared_mutex` |
| 34701686320 | FAILED link | missing `CemuUtil`, `UniformTypeIdentifiers`, `g_isGPUInitFinished` â†’ added |
| 34702277532 | FAILED build | C++ PCH applied to libucontext `trampoline.c` â†’ `SKIP_PRECOMPILE_HEADERS` |
| 34702849057 | FAILED link | `Fiber.h` include path; missing `makecontext.c`; missing `CemuResource` â†’ fixed |
| **34703439905** | **SUCCESS** | **`ZephyrU.app` built and linked for `arm64-apple-ios26.0`** |
| 34704088499 | SUCCESS | binary verified: `Mach-O 64-bit executable arm64`, `minos 26.0`; artifacts `ZephyrU-app-22`, `ios-build-logs-22` |
| 34706976321 | SUCCESS | AGENTS.md handoff; first device install (crashed at dyld init, see traps) |
| 34708990932 | SUCCESS | AArch64 interface CodeGenerators constructed lazily; app survives dyld init |
| 34712079129 | SUCCESS | path diagnostics; found `controllerProfiles` created relative (LTO symbol duplication) |
| 34713931394 | SUCCESS | LTO disabled on iOS; `nm` shows single `ActiveSettings::s_config_path` / `GetConfigHandle()::config` |
| 34714878411 | SUCCESS | `cemuLog_createLogFile` in core init; M0+M1 verified on device (`core initialized (JIT: no)`) |
| 34716250963 | SUCCESS | emulator view backed by CAMetalLayer (fixes start crash); title load reaches title identification |
| 34717177861 | SUCCESS | swipe-to-delete for imported games |
| 34718970910 | SUCCESS | parse reason logged; `NO_DISC_KEY` for the imported `.wux`; keys.txt import from Documents |
| 34719375285 | SUCCESS | JIT probe via mmap+mprotect: reported available without a debugger (false positive) |
| adb082b | PENDING | probe executes a `ret` stub to verify executable memory for real |

## Device bring-up log (iPhone 17 Pro, iOS 27.0 `24A5430a`)

Installation uses the workflow in `docs/IOS_DEVICE_BRINGUP.md`: download the CI app artifact,
re-sign with the development profile (`get-task-allow`), `devicectl device install`, launch with
`--console`, pull `Library/Application Support/log.txt`.

Three issues were found and fixed on the way to M1:

1. **SIGABRT before `main` (dyld static initializers).** The AArch64 backend had three global
   `AArch64GenContext_t` objects whose constructors allocate executable memory through xbyak.
   Without JIT that allocation throws during dyld init, before `main` can select the interpreter.
   Fixed by constructing them lazily inside
   `PPCRecompilerAArch64Gen_generateRecompilerInterfaceFunctions()`.
2. **Duplicate vague-linkage symbols under LTO.** ThinLTO internalized inline variables and
   function-local statics per static library, so the binary contained two copies of
   `ActiveSettings::s_config_path` and `GetConfigHandle()::config`; the bridge wrote one copy while
   the core read the other, making `GetConfigPath()` return relative paths (`controllerProfiles`)
   and directory creation fail with `Operation not permitted`. Fixed by disabling
   `CMAKE_INTERPROCEDURAL_OPTIMIZATION_*` when `CEMU_IOS=ON`; verified with `nm` on the artifact.
3. **Free developer profile constraints.** A free Apple ID team allows at most three
   development-signed apps per device and profiles expire after 7 days. Keep one slot free or
   uninstall an app before installing, and re-run automatic signing to refresh the profile.

For debug builds, `devicectl` already forwards the app's `stderr` when launched with `--console`;
`NSLog` output appears there. `cemuLog` output is written to `log.txt` in the app's Application
Support directory.

### Title loading and JIT findings

- First imported title (`.wux`) fails to parse with `invalid reason 3` (`NO_DISC_KEY`): the image is
  encrypted. ZephyrU copies a user-supplied `Documents/keys.txt` into the user data path, where
  Cemu's `KeyCache` reads it; no keys are ever bundled. A decrypted `.wua`/`.rpx` avoids this.
- `-[EmulatorViewController viewDidLoad]` used to crash because the `layerClass` override sat on
  the view controller instead of a `UIView`; the emulator view is now an `EmulatorMetalView`.
- Unattended test hooks: `--autostart` starts the first imported game, `--autostop <seconds>`
  stops it, and a telemetry line (`running`, `frameCounter`, `drawCalls`, compiled shaders,
  thermal state) is written to `log.txt` every ~4 s.
- The game list supports swipe-to-delete for imported games.
- JIT probe: `mprotect(PROT_EXEC)` can *report* success on iOS while execution still faults, so the
  probe now writes an AArch64 `ret` stub and executes it under a signal guard. The recompiler is
  only selected when execution actually works.
- LLDB attach works with `devicectl device process launch --start-stopped` followed by
  `device process attach -p <pid> -c` in `xcrun lldb` (Xcode 26.5).

Pre-emptive iOS fixes applied while builds ran (verified against Darwin APIs):
`GetTickCount`, `HighResolutionTimer`, `pthread_setname_np`, `cpu_features`, `MMU.h` endian macros,
`Common/platform.h`, `precompiled.h` swap/steady-clock, `LatteAddrLib_Coord`, `coreinit_MCP`,
`DSUControllerProvider`, `CafeSystem` RAM/OS-version reporting.

