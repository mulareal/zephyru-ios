# ZephyrU — Cemu on iOS

ZephyrU ports the [Cemu](https://github.com/cemu-project/Cemu) Wii U emulator to iOS arm64,
targeting *The Legend of Zelda: The Wind Waker HD* on iPhone 17 Pro (A19 Pro, iOS 26) first.

The presentation target is a correctly emulated 30 FPS game at 100% speed, presented on the
120 Hz ProMotion display through MetalFX frame interpolation — never a fake "native 120 FPS".

## Layout

| Path | Purpose |
|---|---|
| `docs/IOS_PORT_RESEARCH.md` | Sourced research: Cemu architecture, iOS JIT policy, MetalFX, display/audio/input APIs |
| `docs/IOS_PORT_STATUS.md` | Living component/milestone status with blockers |
| `patches/0001-zephyru-cemu-core.patch` | Minimal diff against pinned upstream Cemu (`3310f3b`) |
| `ios/` | iOS platform layer + UIKit application (overlay) |
| `scripts/apply_port.sh` | Clones pinned Cemu and applies patch + overlay |
| `scripts/ios-vcpkg.json` | iOS-trimmed vcpkg dependency manifest |
| `.github/workflows/ios.yml` | macOS CI that produces a real `arm64-apple-ios` build |

## Building

On macOS with Xcode 26 and a bootstrap of [vcpkg](https://github.com/microsoft/vcpkg):

```bash
bash scripts/apply_port.sh
cp scripts/ios-vcpkg.json cemu/vcpkg.json
cmake -S cemu -B build-ios -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET=arm64-ios -DENABLE_VCPKG=OFF -DCEMU_IOS=ON
cmake --build build-ios --config Release --target ZephyrU -j8
```

The CI workflow performs exactly these steps and uploads logs for every run.

## Emulator backends on iOS

- **CPU**: upstream IML recompiler with the existing AArch64 backend (`BackendAArch64`,
  xbyak_aarch64) when executable memory is available (development-signed build attached to a
  debugger). Otherwise the emulator runs Cemu's PowerPC interpreter
  (`CPUMode::SinglecoreInterpreter`) and says so in the UI. See research doc §3.
- **GPU**: upstream native Metal renderer (`src/Cafe/HW/Latte/Renderer/Metal`) with an iOS
  CAMetalLayer surface. No Vulkan/MoltenVK indirection.
- **Audio**: `AudioUnitAPI`, a RemoteIO AudioUnit backend implementing Cemu's `IAudioAPI`.
- **Input**: `GameControllerProvider` on Apple's GameController framework, plus the same default
  mapping as the desktop SDL provider.

## Legal

ZephyrU contains no game code, keys, or copyrighted data. It only runs titles the user has
imported; you must own the game. Cemu is licensed under the MPL-2.0; port changes are provided
as a patch series against upstream.
