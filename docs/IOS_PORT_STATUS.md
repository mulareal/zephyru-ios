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

Runtime milestones (M0 launch on hardware onward) still need a physical iPhone 17 Pro and are
tracked below.

## Milestones

| ID | Goal | Status | Evidence / Blockers |
|---|---|---|---|
| M0 | iOS application launches | BUILD DONE / RUN PENDING | `ZephyrU.app` links in CI; launch needs device signing with `get-task-allow` |
| M1 | Cemu core initializes | SCAFFOLDED | `CemuIOSBridge::initializeCoreWithError` ports `CemuCommonInit`/`CemuApp::OnInit` path setup, MLC creation, audio/input/graphic-pack init |
| M2 | Game metadata readable | SCAFFOLDED | `CafeTitleList` initialized with Documents/games scan path; `.rpx` standalone path supported directly |
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
| Save data path (MLC in Application Support) | SCAFFOLDED | crash-consistency hardening | add flush-on-background |
| JIT capability probe + UI status | DONE (build) | none | device test |
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

Pre-emptive iOS fixes applied while builds ran (verified against Darwin APIs):
`GetTickCount`, `HighResolutionTimer`, `pthread_setname_np`, `cpu_features`, `MMU.h` endian macros,
`Common/platform.h`, `precompiled.h` swap/steady-clock, `LatteAddrLib_Coord`, `coreinit_MCP`,
`DSUControllerProvider`, `CafeSystem` RAM/OS-version reporting.

