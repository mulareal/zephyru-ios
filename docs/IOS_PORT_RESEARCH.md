# ZephyrU — iOS Port Research: Cemu → iPhone 17 Pro (A19 Pro)

Status: living document. Last updated 2026-09-12.
Upstream baseline: `cemu-project/Cemu` `main` @ `3310f3b8b184d64a62b89fd59088c799432badf5` ("Vulkan: Experimental barrier skip when the game does not request it").

This document records verified findings only. Every architectural assumption carries a source:
upstream file path + line, Apple documentation URL, or both. Unverified items are marked **UNVERIFIED**.

---

## 0. Target environment (verified)

| Item | Value | Source |
|---|---|---|
| Device | iPhone 17 Pro, A19 Pro, Apple10 GPU family, 12 GB RAM | Metal Feature Set Tables (May 21 2026) map "A19-series → Metal 3 & 4, Apple10"; Apple ProMotion article lists "iPhone 17 and later" |
| OS | iOS 26.x | iPhone 17 Pro ships iOS 26 |
| Display | ProMotion 10–120 Hz (iPhone), `CADisableMinimumFrameDurationOnPhone` required for >60 Hz | https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays |
| Metal | Metal 4 supported (Apple7+; A14+; iPhone 12+) | https://developer.apple.com/videos/play/wwdc2025/205/ , https://support.apple.com/en-us/102894 |
| GPU family | Apple10 ≥ Apple7 (temporal upscaler min) ≥ Apple5 (frame interpolator min) | https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf |

---

## 1. Method & evidence rules

1. Upstream source was cloned shallow at the commit above and inspected directly (`cemu/` in this workspace). Claims about Cemu cite `path:line`.
2. Apple-API claims cite developer.apple.com pages fetched during this research (2026-09-12), including the `.md` availability metadata Apple serves for DocC pages.
3. Claims that could not be verified with primary sources are explicitly marked **UNVERIFIED** and are not load-bearing.

---

## 2. Cemu upstream architecture (verified from source)

Cemu is a C++20 CMake project. Targets relevant to a port:

| Target | Location | Notes |
|---|---|---|
| `CemuCafe` | `src/Cafe/CMakeLists.txt` | The emulator core. RPL loader, IOSU, Latte (GPU), Espresso (PPC), GX2, gx2, snd_core/ax, ICP, etc. |
| `CemuCommon` | `src/Common/CMakeLists.txt` | Platform base: `MemMapper`, `FileStream`, `SysAllocator`, sockets, exception handler |
| `CemuComponents` | `src/Cemu/CMakeLists.txt` | Logging, crypto (ncrypto), napi, nex, PPCAssembler, DownloadManager |
| `CemuConfig` | `src/config/` | `CemuConfig`, `ActiveSettings` (paths), `LaunchSettings` |
| `CemuInput` | `src/input/CMakeLists.txt` | Input provider abstraction (SDL/XInput/DInput/DSU/Wiimote/Keyboard) |
| `CemuAudio` | `src/audio/CMakeLists.txt` | `IAudioAPI` abstraction (Cubeb/XAudio/DirectSound) |
| `CemuGui` | `src/gui/CMakeLists.txt` | **INTERFACE** library exposing `src/gui/interface`; links `CemuWxGui` only when `ENABLE_WXWIDGETS=ON` |
| `CemuWxGui` | `src/gui/wxgui/` | Desktop UI; implements `WindowSystem::Create()` (`src/gui/wxgui/wxWindowSystem.cpp`) and the app loop (`CemuApp::OnInit`) |
| `CemuBin` | `src/CMakeLists.txt` | Desktop executable (`src/main.cpp`) |

### 2.1 The core is GUI-decoupled except for one interface (key finding)

`git grep -l '#include "gui/' src/Cafe` returns **zero files**. The only GUI dependency of the core is the header
`src/gui/interface/WindowSystem.h` plus imgui usage in `LatteOverlay.cpp`, `LatteShaderCache.cpp`, `MetalRenderer.cpp`.
`WindowSystem.h` itself has no wxWidgets dependency (it includes only `input/api/ControllerState.h`).

Consequence: an iOS target can build the core with `ENABLE_WXWIDGETS=OFF` (leaving `CemuGui` as an interface target)
and provide an iOS implementation of the `WindowSystem` free functions. This is the intended seam, not a hack:
the wx implementation lives entirely under `src/gui/wxgui/`.

`WindowSystem` API surface used by the core (from `WindowSystem.h` and grep of call sites):
`ShowErrorDialog`, `GetWindowInfo`, `GetWindowSize/GetPadWindowSize/GetWindowPhysSize/GetPadWindowPhysSize`,
`GetWindowDPIScale/GetPadDPIScale`, `IsPadWindowOpen`, `IsKeyDown`, `GetKeyCodeName`, `InputConfigWindowHasFocus`,
`UpdateWindowTitles`, `NotifyGameLoaded`, `NotifyGameExited`, `RefreshGameList`, `IsFullScreen`, `CaptureInput`.

### 2.2 Embedding API (key finding)

`src/Cafe/CafeSystem.h` exposes an embedding surface:

- `CafeSystem::Initialize()` / `Shutdown()`
- `CafeSystem::SetImplementation(SystemImplementation*)` with `CafeRecreateCanvas()` and `CafePPCProcessExit()`
- `PrepareForegroundTitle(TitleId)` / `PrepareForegroundTitleFromStandaloneRPX(path)`
- `LaunchForegroundTitle()`, `IsTitleRunning()`, `ShutdownTitle()`
- `GetForegroundTitleName/Region/SDKVersion/...`, `g_isGPUInitFinished`

`src/main.cpp` contains the desktop-only driver (`CemuCommonInit()`); wx calls it from `CemuApp::OnInit`
(`src/gui/wxgui/CemuApp.cpp:344`). The iOS app replaces exactly this layer.

### 2.3 Build-system facts

- Architectures: `CEMU_ARCHITECTURE` = `CMAKE_OSX_ARCHITECTURES` (Apple) else `CMAKE_SYSTEM_PROCESSOR` (`CMakeLists.txt:257-263`).
  When it matches `aarch64|arm64`, `dependencies/xbyak_aarch64` is added and `BackendAArch64.cpp` is compiled
  (`src/Cafe/CMakeLists.txt:621`). For iOS with `CMAKE_OSX_ARCHITECTURES=arm64` this selects automatically.
- Option set relevant to iOS: `ENABLE_WXWIDGETS`, `ENABLE_OPENGL`, `ENABLE_VULKAN`, `ENABLE_METAL`, `ENABLE_CUBEB`,
  `ENABLE_SDL`, `ENABLE_LIBUSB`, `ENABLE_HIDAPI`, `ENABLE_DISCORD_RPC` (`CMakeLists.txt:120-146`).
- `ENABLE_METAL` is forced ON for `APPLE` (`CMakeLists.txt:103-107`); `include_directories(dependencies/metal-cpp)`.
- Dependencies are vcpkg (boost subsets, curl, openssl, glslang, fmt, glm, pugixml, rapidjson, zlib, zstd, libzip,
  libpng, sdl3, wxwidgets, tiff, libusb), plus in-tree submodules: `ZArchive`, `cubeb`, `imgui`, `metal-cpp`,
  `xbyak_aarch64`, `Vulkan-Headers`, `ih264d` (in-tree, `dependencies/ih264d`).
- `src/Common/CMakeLists.txt` chooses `windows/` vs `unix/` sources by `WIN32`; Apple builds use the unix set
  (`FileStream_unix.cpp`, `platform.cpp`) which is POSIX and compiles on iOS.

---

## 3. CPU emulation: PowerPC → ARM64 (verified)

### 3.1 What upstream already provides

Cemu's recompiler is a two-stage design:

1. PPC → IML (architecture-neutral SSA-ish IR): `src/Cafe/HW/Espresso/Recompiler/PPCRecompilerImlGen.cpp`, `IML/`.
2. IML → target ISA backends:
   - x86-64: `BackendX64/` (not used on iOS)
   - **AArch64: `BackendAArch64/BackendAArch64.cpp` (1553 lines) using `xbyak_aarch64`** (Fujitsu) for instruction emission.
     Allocated via `MemMapper::AllocateMemory(..., P_RWX)` (mirrors x64 at `BackendX64.cpp:1321`).
3. Runtime entry points: `PPCRecompiler_init()` (`PPCRecompiler.cpp:663`) reserves instance data, emits interface
   functions via `PPCRecompilerAArch64Gen_generateRecompilerInterfaceFunctions()` under `#elif defined(__aarch64__)`
   (`PPCRecompiler.cpp:686-687`), allocates the trampoline/code ranges, and starts the recompiler worker thread.

Instruction cache maintenance for generated code is **UNVERIFIED** in this document: no
`__builtin___clear_cache`/`isb` call was found in the grepped emit path; this must be confirmed on device, because
Apple's AArch64 requires explicit I-cache synchronization after writing code (Apple's JIT guidance). **Action item.**

### 3.2 Fibers: ucontext is stubbed on iOS (port-specific)

Cemu's scheduler is built on cooperative fibers (`src/util/Fiber/FiberUnix.cpp`) implemented with POSIX
`ucontext` (`getcontext`/`makecontext`/`swapcontext`). On iOS these functions are **not implemented**:
Apple's Libc provides stubs returning `ENOTSUP`. The functions are declared in the SDK and link, but never
switch context, so the emulator would deadlock or crash at runtime.

Sources:
- Porting reports: https://stackoverflow.com/questions/7470186/iphone-makecontext-swapcontext (Apple Libc
  `context-stubs.c` returns ENOTSUP) and https://butenkoms.space/coroutines-on-ios/.
- QEMU/UTM hit the same issue and added `libucontext` as an iOS-specific coroutine backend:
  https://patchew.org/QEMU/20201012232939.48481-1-j@getutm.app/20201012232939.48481-7-j@getutm.app/
  ("iOS does not support ucontext natively for aarch64 ... As a workaround we include a library
  implementation of ucontext").

Decision: vendor **libucontext** (ISC-style license, AArch64 assembly, already handles `__MACH__`
underscore prefixing in `arch/common/common-defs.h`) under `ios/third_party/libucontext/`, and compile it
into `CemuUtil` on iOS in place of `FiberUnix.cpp` via the new `ios/platform/FiberIOS.cpp`. One behavioral
difference is intentional and documented in that file: libucontext reads `makecontext` varargs as 64-bit
words, so the fiber entry parameter is passed as a single argument instead of Cemu's two-int split for
Apple's macOS `makecontext` ABI.

### 3.3 Interpreter fallback (JIT-less correctness path)
- `CPUMode::SinglecoreInterpreter` short-circuits `PPCRecompiler_init()` before any executable-memory allocation
  (`PPCRecompiler.cpp:666-670`), logging "Using singlecore interpreter".
- `LaunchSettings::ForceInterpreter()` / `ForceMultiCoreInterpreter()` (`src/config/LaunchSettings.h:37-38`) force
  interpreter paths; `CafeSystem.cpp:912` branches on them.
- Interpreters: `PPCInterpreterImpl.cpp` (`PPCInterpreterSlim_executeInstruction`, `PPCInterpreterFull_executeInstruction`),
  `PPCInterpreterALU/FPU/OPC/PS/LoadStore`.
- Consequence: the port can *always* boot correctness-first without JIT, and switch to the AArch64 recompiler when
  executable memory is available. This directly satisfies the "do not say JIT is unavailable and give up" requirement:
  both paths are upstream-supported; only the MemMapper and the JIT-enablement story are iOS-specific.

### 3.4 Executable memory on iOS (primary sources)

- Apple Platform Security: W+X pages "can be used only by apps under tightly controlled conditions: the kernel checks
  for the presence of the Apple-only dynamic code-signing entitlement" — used by Safari's JIT.
  https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web
- `mmap` man page: without `MAP_JIT`, a W+X mapping "will fail with MAP_FAILED on macOS. A writable, but not executable
  mapping is returned on iOS, watchOS and tvOS." https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon
- `com.apple.security.cs.allow-jit` is documented **macOS 10.7+**.
  https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-jit
- On iOS, JIT is granted to Apple-authorized alternative browser engines via BrowserEngineKit:
  "Allow execution of JIT-compiled code entitlement" (`com.apple.security.cs.allow-jit`) plus
  `com.apple.security.cs.jit-write-allowlist`, with `be_memory_inline_jit_restrict_rwx_to_rx_with_witness(...)`.
  https://developer.apple.com/documentation/browserenginekit/protecting-code-compiled-just-in-time
  This path is gated to browser engines (DMA/EU/Japan) and Apple denied iSH's request to widen it:
  https://ish.app/blog/ish-jit-and-eu ; Dolphin's request was denied too:
  https://oatmealdome.me/blog/why-dolphin-isnt-coming-to-the-app-store

### 3.5 The sanctioned development mechanism (no exploits)

- Development-signed apps carry `get-task-allow`; attaching a debugger sets `CS_DEBUGGED`
  (`#define CS_DEBUGGED 0x10000000 /* ... allowed to run with invalid pages */` in xnu `bsd/sys/codesign.h`), and
  `cs_allow_invalid()` calls `vm_map_cs_wx_enable()` to re-enable W/X for the process
  (https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_cs.c).
- TN2415: `get-task-allow` "determines whether Xcode's debugger can attach to the app"
  https://developer.apple.com/library/archive/technotes/tn2415/_index.html
- Sideloaded (development-signed) apps can be JIT-enabled by debugger attach; on-device tooling exists:
  StikDebug (iOS 17.4+) https://github.com/StikDebug/StikDebug , SideStore
  https://docs.sidestore.io/docs/advanced/jit , AltStore https://faq.altstore.io/altstore-classic/enabling-jit .
- **iOS 26 regression / moving target:** DolphiniOS states that on iOS 26 with TXM (A15+/M2+), Xcode attach alone no
  longer enables JIT; StikDebug 2.3.0+ provides the new method
  https://oatmealdome.me/blog/dolphinios-5-0-0-beta-1 . SideStore's JIT page (2026-06-17) still lists limited
  compatibility ("iOS 26 has broken JIT once again, and 26.6 and 27 only work with a few apps… DolphiniOS (Works up
  to 26.6)") https://docs.sidestore.io/docs/advanced/jit . iPhone 17 Pro/A19 Pro is a TXM device on iOS 26.
- Therefore: **JIT availability on the target is an operational risk, not an architectural blocker.** The port ships
  both backends and detects availability at runtime.

### 3.6 Decision (EVIDENCE → HYPOTHESIS → DECISION)

- Evidence: AArch64 recompiler exists upstream and is selected automatically for arm64; JIT requires `CS_DEBUGGED`
  (dev-signed + debugger) on iOS; interpreter fallback exists upstream.
- Hypothesis: iOS can reach playable speed only through the AArch64 recompiler; interpreter is a correctness fallback.
- Implementation: `MemMapperIOS.cpp` (new) attempts RWX `mmap`; on failure it reports a precise error and the app
  selects `CPUMode::SinglecoreInterpreter` (or forces interpreter) instead of crashing.
- Measurement: once a physical device + JIT enabler is available, benchmark recompiled vs interpreted blocks/s.
  Until then the interpreter path is the CI-verifiable default.

---

## 4. GPU / GX2 → Metal (verified)

Upstream already contains a first-class Metal renderer: `src/Cafe/HW/Latte/Renderer/Metal/`
(~40 files; `MetalRenderer.cpp` is 2369 lines). It uses **metal-cpp** (`dependencies/metal-cpp`), i.e. C++ bindings,
not Objective-C. The GX2→Metal translation layer is `LatteToMtl.cpp`, with pipeline/sampler/depth-stencil caches and
an MSL path from the legacy shader decompiler (`LatteDecompilerEmitMSL*.cpp`).

iOS-specific deltas required:

1. **Surface creation.** `MetalLayerHandle` obtains the layer via `CreateMetalLayer(windowInfo.surface, ...)`
   (`Metal/ MetalLayerHandle.cpp:8-13`), where `surface` is the platform window view from `WindowSystem`. On macOS
   `MetalLayer.mm` creates an `NSView`-hosted `CAMetalLayer`. On iOS the equivalent creates/returns a
   `CAMetalLayer` for a `UIView` — the renderer only needs `nextDrawable()`/`drawableSize`, so no renderer-core
   changes are required. `MetalView.mm` (AppKit) is replaced by an iOS implementation.
2. **Present.** `SwapBuffer(bool)` calls `commandBuffer->presentDrawable(drawable)`
   (`MetalRenderer.cpp:2297-2304`). For frame pacing/frame generation later, replace with
   `present(_:atTime:)` / `present(_:afterMinimumDuration:)` at the presentation stage. `presentDrawable:atTime:` and
   `afterMinimumDuration:` are documented APIs:
   https://developer.apple.com/documentation/metal/mtlcommandbuffer/present(_:attime:) ,
   https://developer.apple.com/documentation/metal/mtlcommandbuffer/present(_:afterminimumduration:)
3. **imgui.** The core calls `ImGui_ImplMetal_Init` etc. (`MetalRenderer.cpp:2310`). imgui's Metal backend is
   Metal-API-based, so it compiles for iOS; the overlay input source differs but is already funneled through
   `WindowSystem`.
4. **Shaders.** MSL generation and the shader cache are platform-independent
   (`LatteShaderCache.cpp` serializes to disk; `MetalPipelineCompiler.cpp` builds pipelines). Metal 4 on iOS 26 adds
   `MTL4Compiler`, pipeline dataset serialization, and offline `metal-tt` binary archives
   https://developer.apple.com/documentation/metal/using-the-metal-4-compilation-api — the documented cure for
   first-use shader-compile stutter. This is the planned Phase-3 upgrade; the initial port uses the existing cache.

### 4.1 Wind Waker HD-specific GX2 surface

Wind Waker HD is a first-party Wii U title rendering primarily 1280×720 with a fixed 30 Hz update. It exercises
GX2 render targets, depth copies, and texture streaming typical of Cemu's supported feature set. The port's first
graphics goal is parity with the existing Metal backend, not new translation work.

---

## 5. MetalFX upscaling and frame interpolation (verified against Apple docs)

Availability metadata was read from Apple's DocC JSON/markdown for each symbol (`.md` endpoints emit the raw
availability array):

| Symbol | iOS availability | Evidence |
|---|---|---|
| `MTLFXSpatialScaler` | iOS 16.0+ | https://developer.apple.com/documentation/metalfx/mtlfxspatialscaler |
| `MTLFXTemporalScaler` | iOS 16.0+ | https://developer.apple.com/documentation/metalfx/mtlfxtemporalscaler |
| `MTLFXTemporalDenoisedScaler` | iOS 18.0+ | https://developer.apple.com/documentation/metalfx/mtlfxtemporaldenoisedscaler |
| **`MTLFXFrameInterpolator`** | **iOS 26.0+** — verified by fetching `.../mtlfxframeinterpolator.md`: `"availability": ["iOS: 26.0.0 -", ...]` | https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolator.md |
| `MTL4FXFrameInterpolator` | iOS 26.0+ | https://developer.apple.com/documentation/metalfx/mtl4fxframeinterpolator |

Chip support (Metal Feature Set Tables, May 21 2026): "MetalFX frame interpolation — Metal 3 & 4 — Apple5";
"A19-series — Metal 3 & 4 — Apple10". Therefore A19 Pro **meets or exceeds** the frame-interpolation family floor.

### 5.1 I/O contract (what the emulator must synthesize)

`MTLFXFrameInterpolatorBase` inputs: `colorTexture`, `prevColorTexture`, `depthTexture`, `motionTexture`,
optional `uiTexture`, optional `distortionTexture`, `outputTexture`; per-frame scalars include
`motionVectorScaleX/Y`, `jitterOffsetX/Y`, `deltaTime`, `fieldOfView`, `nearPlane`, `farPlane`,
`isDepthReversed`, `isUITextureComposited`, `shouldResetHistory`.
https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatorbase
Apple's integration guide uses `RGBA16Float` color/output, `Depth32Float` depth, `RG16Float` motion; motion is
"screen-space pixel displacement"; output requires `MTLTextureUsageShaderWrite`.
https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/using-metalfx-frame-interpolation/SKILL.md
WWDC25 session 211 confirms: two rendered frames + motion + depth → **one** generated in-between frame, with a
recommended dual-present cadence (`presentDrawable:afterMinimumDuration:` and a pacing thread).
https://developer.apple.com/videos/play/wwdc2025/211/

### 5.2 Consequence for a 30 FPS title (important, honest)

- 30 native → 60 presented = exactly one interpolated frame per rendered pair. **API-supported directly.**
- 30 native → 120 presented requires three interpolated frames per pair. The public MetalFX frame interpolator
  generates **one** intermediate frame per call; there is no documented Nx multiplier. Reaching 120 from 30 native
  therefore requires an emulator-specific multi-frame interpolation experiment (Phase 7) — or rendering at 60.
- 60 native → 120 presented = one interpolated frame per pair: directly supported. This is why the "real 60 FPS
  simulation" investigation (Phase 7 / success level 9) matters: it is the clean route to 120 Hz presentation.
- Motion vectors: Apple provides **no** motion-vector generator; all MetalFX temporal effects require app-supplied
  motion. An emulator can synthesize them from GX2 draw transforms (vertex shader transform × previous-frame
  transform) where available; otherwise image-space estimation must be evaluated.
- The emulator's own camera/vertex data makes per-draw motion reconstruction feasible for the majority of GX2 draws
  (each draw knows its MVP matrix and previous one), but skinned/particle draws need care. This is a phase-7
  research item with explicit correctness criteria (no ghosting, no UI tearing).

### 5.3 Decision

- Phase 6 target: 30 native / 30 rendered / 30 presented, perfectly paced.
- Phase 7a: 30 native / 30 rendered / 60 presented with MetalFX frame interpolation, gated on
  `MTLFXFrameInterpolatorDescriptor.supportsDevice(_:)` and iOS >= 26.
- Phase 7b: investigate 60 native simulation patch for Wind Waker HD (see §7), then 60→120.
- No recursive/blind interpolation.

---

## 6. Display, pacing and lifecycle (verified)

- ProMotion: iPhone ProMotion supports 10–120 Hz; `CADisableMinimumFrameDurationOnPhone = YES` is required to allow
  >60 Hz on iPhone; rates are quantized to factors of the max refresh; the system clamps under Low Power Mode and
  thermal pressure.
  https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
  https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone
- `CAMetalDisplayLink` (iOS 17+) provides `drawable`, `targetTimestamp`, `targetPresentationTimestamp`, and
  `preferredFrameLatency` (only 1.0 or 2.0). This is the recommended pacing mechanism for a Metal app that owns its
  own render loop.
  https://developer.apple.com/documentation/quartzcore/cametaldisplaylink and `.../update`
- Presentation timing APIs: `presentDrawable:atTime:`, `presentDrawable:afterMinimumDuration:`,
  `addPresentedHandler(_:)`, `MTLDrawable.presentedTime` — used for measured frame pacing rather than assumed pacing.
- Lifecycle: `AVAudioSession.interruptionNotification` with `.shouldResume`
  https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions ; `ProcessInfo.thermalState`
  (+ notification) for adaptive quality https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property
- The emulator must pause/resume the emulation and Latte threads on `scenePhase` transitions; the render loop must not
  keep burning GPU/CPU in background (iOS will terminate otherwise, and it is the right thing to do).

---

## 7. Wind Waker HD timing (30 Hz) and the 60 FPS experiment

- The Wii U game logic runs on the PowerPC under Cemu's scheduler; frame timing derives from the GX2 swap/present
  cadence and the Espresso timebase. Cemu's `LatteThread` drives rendering and `LatteTiming` derives the game's
  frame delta.
- Changing the game's own update rate is **not** a host-side setting. A real 60 FPS patch must:
  1. Find the per-frame update function(s) and the frame-delta constant used by the game,
  2. Split logic from rendering where the game hard-codes 30 Hz,
  3. Preserve real-world timing (physics, cutscenes, audio sync, scripted events).
- This will be a phase-7 investigation with gameplay-comparison tests (no speed-hack heuristics). Until then the
  project renders 30 Hz natively and presents at 60/120 via frame interpolation.

---

## 8. Audio (verified)

- Lowest-latency documented iOS output path: RemoteIO AudioUnit, or `AVAudioEngine` + `AVAudioSourceNode` render
  block (same real-time callback semantics).
  https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioUnitHostingGuide_iOS/UsingSpecificAudioUnits/UsingSpecificAudioUnits.html
  https://developer.apple.com/documentation/avfaudio/avaudiosourcenode
- `setPreferredIOBufferDuration`: floor "at least 0.005 s (256 frames) but might be lower depending on the hardware".
  https://developer.apple.com/documentation/avfaudio/avaudiosession/setpreferrediobufferduration(_:)
- Cemu's `IAudioAPI` contract is small and blocking-free: `NeedAdditionalBlocks()`, `FeedBlock(sint16*)`,
  `Play()`, `Stop()`; the core pushes S16 blocks (`src/audio/IAudioAPI.h`; `CubebAPI.cpp` is the reference
  implementation). An `AudioUnitAPI` backend that feeds a lock-protected ring buffer inside the render callback
  mirrors the Cubeb design exactly. `kBlockCount = 24` blocks of buffering already absorbs CPU spikes.
- Audio must never drive emulation speed: in Cemu the audio API only consumes blocks; the PPC timebase drives
  timing. Keep that invariant.

---

## 9. Input (verified)

- Apple's GameController framework: `GCController.controllers()`, connect/disconnect notifications, profiles
  `extendedGamepad`, `GCDualSenseGamepad`, `GCXboxGamepad`, `GCMotion`; buffered live input via
  `GCControllerLiveInput` + `GCDevicePhysicalInput.inputStateQueueDepth`/`nextInputState()` (iOS 17+), and
  `GCKeyboard` for keyboards.
  https://developer.apple.com/documentation/gamecontroller/gccontroller ,
  https://developer.apple.com/documentation/gamecontroller/gcdevicephysicalinput ,
  https://developer.apple.com/documentation/gamecontroller/gckeyboard
- Apple documents no >1 kHz polling contract (**UNVERIFIED** whether the framework coalesces); the buffered
  `nextInputState()` drain is the correct pattern, and input must be sampled independently of the 30 FPS render loop.
- Cemu's `CemuInput` uses providers: `ControllerProviderBase` + `Controller<TProvider>` implementing
  `raw_state()`/`is_connected()`. A `GameControllerProvider` on iOS is a direct analogue of
  `SDLControllerProvider` (`src/input/api/SDL/`).
- Touch overlay: a SwiftUI/UIKit overlay writes directly into the same provider state; it is never in the emulation
  thread's critical path.

---

## 10. Memory, entitlements and sandbox (verified)

- Public entitlements relevant to this project:
  - `com.apple.developer.kernel.increased-memory-limit` (iOS 15+) — may exceed the default jetsam limit on supported
    devices; "not guaranteed"; query `os_proc_available_memory()`.
    https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit
  - `com.apple.developer.kernel.extended-virtual-addressing` (iOS 14+) — extended address space (the Wii U guest
    address space reservation touches this).
    https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.extended-virtual-addressing
- `os_proc_available_memory()` is advisory-only; the app must degrade gracefully
  https://developer.apple.com/documentation/os/os_proc_available_memory
- Measured (single developer, 12 GB iPhone, **UNVERIFIED** as official): ~6144 MB available with
  `increased-memory-limit`. Apple publishes no per-device caps. Design for ~4–5 GB usable and make guest RAM
  (2 GB Wii U) plus caches fit; iOS compresses and swaps aggressively, and unified memory means the guest RAM is the
  same pool the GPU uses.
- Sandbox: all game/MLC/cache data must live under the app container (`Documents`, `Library/Application Support`,
  `Library/Caches`). `ActiveSettings::SetPaths(...)` (`src/config/ActiveSettings.h`) exists precisely to redirect
  these; `UIDocumentPicker`/security-scoped URLs import game files (`.wua`, `.wud`, `.rpx`) into the container.
- The Wii U MLC filesystem must be created inside the container (the wx app does this in
  `CemuApp::InitializeNewMLCOrFail`, which is desktop UI code; the iOS app must reimplement the directory
  initialization using the same `mlc01` layout).

---

## 11. Thermal & sustained performance (verified)

- `ProcessInfo.thermalState` + `thermalStateDidChangeNotification`; Apple explicitly recommends reducing target
  framerate and LOD at `.serious`.
  https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property
  https://developer.apple.com/videos/play/wwdc2019/422/
- Apple warns against oscillating quality from display-link callbacks (feedback loops)
  https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
- Port policy: adaptive **rendering** quality (internal resolution, frame-generation mode, shader work) only; never
  change emulation speed. Sustained tests of 10/30/60 min are part of the milestone/M11 work on device.

---

## 12. Dependency strategy for iOS

Initial iOS configuration (all options exist upstream):

```
-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0
-DCEMU_IOS=ON
-DENABLE_WXWIDGETS=OFF -DENABLE_OPENGL=OFF -DENABLE_VULKAN=OFF -DENABLE_METAL=ON
-DENABLE_CUBEB=OFF -DENABLE_SDL=OFF -DENABLE_LIBUSB=OFF -DENABLE_HIDAPI=OFF -DENABLE_DISCORD_RPC=OFF
```

Required third-party libraries and their iOS story (vcpkg `arm64-ios` triplet supports all of these):
boost subsets (headers + nowide/filesystem/program_options), fmt, glm, pugixml, rapidjson, zlib, zstd,
libzip/ZArchive, libpng, openssl, curl, glslang (Metal backend still uses glslang for SPIRV paths? —
verify during build; MSL path uses its own emitter), `ih264d` (in-tree), `metal-cpp` (in-tree header-only).

Pruning decisions:
- `curl`/`openssl`: needed for `nlibcurl`, `nn_act`, Miiverse stubs and disc key crypto; ship them but disable
  online features initially.
- `boost`: unavoidable (config parsing, filesystem); vcpkg iOS triplet builds are expensive in CI (documented cost).
- `SDL3`: used only for controller events and macOS SDL init; not needed on iOS (GameController.framework replaces it).

---

## 13. Verified risks (ranked)

1. **JIT enablement is the single gating risk.** On iOS 26 + TXM (A19 Pro), Xcode-attached JIT no longer works;
   StikDebug-class debugger attach is required and its compatibility is version-fragile (SideStore: "iOS 26 has
   broken JIT once again…"). Mitigation: dual-backend design; interpreter is CI-verifiable; JIT is a runtime
   capability with a clear UI state ("Recompiler unavailable — running interpreter").
2. **Full core build breadth.** Cemu is a 200k+ LOC desktop emulator. The iOS target must compile the entire core
   (`CemuCafe`) even if runtime code paths are narrowed to Wind Waker HD. Expect a long tail of POSIX/desktop
   assumptions (process spawning, X11-free unix platform code, thread naming, etc.).
3. **vcpkg iOS dependency build time** in CI. Mitigation: cache vcpkg binary cache between runs; accept long first
   build; consider prebuilt iOS deps later.
4. **MetalFX motion-vector quality.** Without correct motion, frame interpolation can ghost badly. The fallback
   presentation mode for 120 Hz without vectors is temporal upscaling + real 30→30 (no interpolation), or 60 Hz.
5. **GPU memory/bandwidth on a phone.** Apple GPUs are TBDR; the Metal backend already targets macOS Apple GPUs,
   which is a strong starting point, but texture cache behavior under memory pressure needs device profiling.

---

## 14. Sources index

Primary Apple documentation (fetched 2026-09-12):
- Platform Security, runtime process: https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web
- Porting JIT compilers to Apple silicon: https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon
- BrowserEngineKit JIT: https://developer.apple.com/documentation/browserenginekit/protecting-code-compiled-just-in-time
- Entitlements: `com.apple.security.cs.allow-jit`, `com.apple.developer.kernel.increased-memory-limit`,
  `com.apple.developer.kernel.extended-virtual-addressing`, `com.apple.security.cs.debugger`
- MetalFX symbols (spatial, temporal, denoised, frame interpolator + Metal 4 variants), Metal 4 compiler/pipeline
  dataset docs, `metal-tt` article
- WWDC 2025 sessions 205 (Metal 4), 211 (MetalFX frame interpolation), 254 (Metal toolchain)
- Metal Feature Set Tables: https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf
- ProMotion: https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
- CAMetalDisplayLink: https://developer.apple.com/documentation/quartzcore/cametaldisplaylink
- GameController: https://developer.apple.com/documentation/gamecontroller/gccontroller
- AudioUnit hosting guide; `setPreferredIOBufferDuration`; `AVAudioSourceNode`
- Thermal state: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property

Upstream code references are inline above as `path:line`.
