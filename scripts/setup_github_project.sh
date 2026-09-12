#!/usr/bin/env bash
# Sets up the ZephyrU GitHub project:
#   - labels
#   - milestones (phase-level)
#   - one issue per work package / milestone
#   - optionally a Projects v2 board (requires the 'project' scope)
#
# Usage:
#   bash scripts/setup_github_project.sh
#
# If the Projects v2 section is skipped, run once:
#   gh auth refresh -s project,read:project
# then re-run this script.
set -euo pipefail

REPO="mulareal/zephyru-ios"
OWNER="mulareal"
PROJECT_TITLE="ZephyrU - iOS Port"

echo "[zephyru] repository: $REPO"

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------
create_label() {
	local name="$1" color="$2" desc="$3"
	gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null
}
create_label "platform"    "1D76DB" "iOS platform layer, lifecycle, sandbox, build system"
create_label "cpu"         "B60205" "PowerPC emulation, IML/AArch64 backend, JIT"
create_label "gpu"         "5319E7" "GX2 to Metal renderer, textures, pipelines, shaders"
create_label "audio"       "FBCA04" "AudioUnit backend, timing, latency"
create_label "input"       "0E8A16" "GameController framework, touch controls"
create_label "ui"          "C2E0C6" "UIKit frontend, overlay, settings"
create_label "performance" "D93F0B" "Frame pacing, CPU/GPU time, thermals, memory"
create_label "framegen"    "F9D0C4" "MetalFX upscaling and frame interpolation"
create_label "docs"        "0075CA" "Documentation and research"
create_label "device"      "FEF2C0" "Requires a physical iPhone 17 Pro"
create_label "blocked"     "000000" "Blocked by an external dependency"
echo "[zephyru] labels ready"

# ---------------------------------------------------------------------------
# Milestones
# ---------------------------------------------------------------------------
existing_milestones=$(gh api "repos/$REPO/milestones?state=all&per_page=100" --jq '.[].title' 2>/dev/null || true)
ensure_milestone() {
	local title="$1" desc="$2"
	if grep -qxF "$title" <<<"$existing_milestones"; then
		echo "[zephyru] milestone exists: $title"
		return
	fi
	gh api "repos/$REPO/milestones" -f title="$title" -f description="$desc" >/dev/null
	echo "[zephyru] milestone created: $title"
}
ensure_milestone "Boot & platform" "M0-M4: app launch, core init, title loading, first PowerPC execution"
ensure_milestone "Graphics & audio" "M5-M9: first GX2 commands, first frames, title screen, gameplay, audio"
ensure_milestone "Performance & presentation" "M10-M13: 100% game speed, thermals, frame interpolation, 120 Hz"

# ---------------------------------------------------------------------------
# Issues
# ---------------------------------------------------------------------------
existing_issues=$(gh issue list --repo "$REPO" --state all --limit 300 --json title --jq '.[].title')
create_issue() {
	local title="$1" labels="$2" milestone="$3" body="$4"
	if grep -qxF "$title" <<<"$existing_issues"; then
		echo "[zephyru] issue exists: $title"
		return
	fi
	local args=(--repo "$REPO" --title "$title" --body "$body" --label "$labels")
	if [ -n "$milestone" ]; then
		args+=(--milestone "$milestone")
	fi
	local url
	url=$(gh issue create "${args[@]}")
	echo "[zephyru] issue created: $url"
}

create_issue \
	"M0: Launch ZephyrU on iPhone 17 Pro" \
	"platform,device" \
	"Boot & platform" \
	"Sign the CI artifact (ZephyrU.app) with a development profile and install it on an iPhone 17 Pro.
Acceptance:
- App launches and the game list UI is interactive.
- JIT status row reports the real executable-memory capability.
- No crash on launch, background and foreground transitions work.

Evidence for the build: docs/IOS_PORT_STATUS.md (Build evidence log)."

create_issue \
	"M1-M2: Core initialization and title scan on device" \
	"platform,device" \
	"Boot & platform" \
	"Verify CemuIOSBridge core initialization on hardware.
Acceptance:
- Config/MLC/games directories are created in the sandbox.
- mlc01 tree and language/country files are written.
- CafeTitleList scans Documents/games and lists imported titles.
- Logs show 'ZephyrU: core initialized' with the correct JIT state."

create_issue \
	"M3-M4: Load Wind Waker HD and execute first PowerPC code" \
	"cpu,device" \
	"Boot & platform" \
	"Load a user-provided title and reach first emulated instructions.
Acceptance:
- PrepareForegroundTitle succeeds (.wua image or standalone .rpx).
- PPC interpreter or AArch64 recompiler starts (per JIT availability).
- First block execution is visible in logs; no fiber/scheduler deadlock.

Note: iOS stubs POSIX ucontext; the fiber scheduler uses the vendored libucontext
backend (research section 3.2). Watch for scheduler stability here."

create_issue \
	"M5-M6: First GX2 commands and first visible frame" \
	"gpu,device" \
	"Graphics & audio" \
	"Validate the Metal renderer surface path on iOS.
Acceptance:
- CreateMetalLayer returns the UIView-backed CAMetalLayer.
- GX2 swap produces a drawable; first frame is presented.
- Clear/draw commands reach the GPU without validation errors (Metal validation on)."

create_issue \
	"M7-M8: Reach title screen and Outset Island" \
	"gpu,device" \
	"Graphics & audio" \
	"Boot Wind Waker HD to gameplay.
Acceptance:
- Title screen renders correctly (no missing textures or broken shaders).
- New game reaches Outset Island; save creation works."

create_issue \
	"M9: Stable low-latency audio (AudioUnit)" \
	"audio,device" \
	"Graphics & audio" \
	"Tune the RemoteIO AudioUnit backend.
Acceptance:
- No crackling under CPU/GPU load spikes.
- Audio does not influence emulation speed.
- Measured output latency documented (buffer size, AVAudioSession values)."

create_issue \
	"M10: 30 FPS / 100% game speed with JIT" \
	"performance,cpu,device,blocked" \
	"Performance & presentation" \
	"Reach the primary baseline: 30 emulated game frames per second at 100% Wii U speed.
Blocker: JIT enablement on iOS 26/TXM (development-signed app attached to a
debugger, StikDebug-class; see research section 3.4/3.5). Without JIT the
interpreter is selected automatically and full speed is not expected.
Acceptance:
- SIMULATION RATE: 30 Hz, game speed 100% (measured over 60 s).
- RENDERED GAME FPS: 30. Frame-time percentiles recorded (avg, 1% low, 0.1% low, worst)."

create_issue \
	"M11: 30/60-minute thermal stability test" \
	"performance,device" \
	"Performance & presentation" \
	"Sustained performance evidence.
Acceptance:
- 10/30/60 minute runs with ProcessInfo.thermalState logging.
- Per-minute game speed and frame times recorded.
- Adaptive quality policy documented and implemented (resolution/LOD, never simulation speed)."

create_issue \
	"M12: MetalFX frame interpolation 30 -> 60" \
	"framegen,gpu" \
	"Performance & presentation" \
	"Implement 30 native -> 60 presented using MTLFXFrameInterpolator (iOS 26+, A19 Pro = Apple10).
Acceptance:
- Feature-gated on supportsDevice; disabled cleanly elsewhere.
- Color/prevColor/depth/motion/ui textures wired per Apple contract.
- Visual comparison against native 30 Hz at 60 presented; no severe ghosting.
- UI overlay reports: simulation 30 Hz / rendered 30 FPS / generated 30 FPS / display 60 FPS."

create_issue \
	"M13: 120 Hz presentation path" \
	"framegen,gpu" \
	"Performance & presentation" \
	"High-refresh presentation.
Options:
- 60 native simulation -> 120 presented via one interpolated frame per pair (API-supported).
- 30 native -> 120 presented requires a custom multi-frame interpolation path (research section 5.2).
Acceptance:
- Display link requests 120 Hz with CAFrameRateRange and CADisableMinimumFrameDurationOnPhone.
- Present timestamps measured (presentedTime), pacing within +/- one refresh interval."

create_issue \
	"Motion-vector synthesis for MetalFX temporal effects" \
	"gpu,framegen" \
	"" \
	"MetalFX requires app-supplied motion vectors (no generator exists in Apple's APIs).
Design:
- Reconstruct per-draw motion from GX2 vertex transforms (current x previous MVP).
- Fallback for skinned/particle draws and image-space estimation evaluation.
Acceptance:
- Documented per-draw coverage for Wind Waker HD.
- Quality measured on device; discard the approach if ghosting is unacceptable."

create_issue \
	"Shader pipeline: Metal 4 pipeline datasets / binary archives" \
	"gpu,performance" \
	"" \
	"Eliminate shader compile stutter using iOS 26 Metal 4 facilities.
Approach:
- MTL4Compiler + MTL4PipelineDataSetSerializer; binary archives; optional metal-tt offline prep.
- Persistent shader/pipeline caches tied to translator version.
Acceptance:
- Cold boot, first playthrough and warm cache measured separately.
- No compilation stalls hidden inside average FPS."

create_issue \
	"Performance overlay: EMU/DISPLAY/GENERATED FPS and stage timings" \
	"ui,performance" \
	"" \
	"Extend the overlay and CemuIOS telemetry.
Required values (kept strictly separate):
- Simulation rate and game speed %
- Native rendered FPS, generated FPS, presented display FPS
- CPU frame time, GPU frame time, framegen time, present time
- RAM, thermal state, dropped frames, shader compilations, input latency estimate"

create_issue \
	"Touch controls overlay for VPAD buttons and sticks" \
	"input,ui" \
	"" \
	"Optional on-screen controls: left/right stick, D-pad, A/B/X/Y, L/R, ZL/ZR, Plus, Minus.
Requirements:
- Input sampled independently of the 30 FPS render loop.
- Overlay must not add measurable render cost.
- Feeds the same provider path as GameController input."

create_issue \
	"Save-data robustness: flush on background/termination" \
	"platform" \
	"" \
	"Never corrupt saves.
Acceptance:
- Flush critical save data on applicationDidEnterBackground and willTerminate.
- Handle memory warnings and audio interruptions without losing state.
- Import/export/backup of save data via Files."

create_issue \
	"Wind Waker HD 60 FPS simulation experiment" \
	"performance,cpu" \
	"" \
	"Investigate a real 60 FPS simulation patch (not interpolation).
Approach:
- Locate frame-delta/update function; split logic vs render; preserve real-world timing.
Acceptance:
- Side-by-side comparison against 30 FPS for physics, animation, collision, scripts, cutscenes, audio.
- No speed-hack accepted as a framerate unlock."

create_issue \
	"Regression tests for interpreter/AArch64 backend and platform layer" \
	"platform,cpu" \
	"" \
	"Port and run upstream correctness tests behind CEMU_IOS:
- PowerPC instruction tests, memory/endianness, shader translation, GX2 state, texture conversion.
- Platform tests: paths, save handling, input mapping.
Acceptance:
- CI job runs the tests on arm64-ios (or macOS host where applicable)."

create_issue \
	"Document JIT enablement and device signing workflow" \
	"docs,device" \
	"" \
	"Create docs/IOS_DEVICE_SETUP.md:
- Development signing with required entitlements (increased-memory-limit, extended-virtual-addressing).
- JIT enablement on iOS 26/TXM (StikDebug-class), limitations, and the interpreter fallback.
- Step-by-step install of the CI artifact; verification checklist (JIT status row, logs)."

# ---------------------------------------------------------------------------
# Optional Projects v2 board
# ---------------------------------------------------------------------------
if gh auth status 2>&1 | grep -q "'project'"; then
	project_number=$(gh project list --owner "$OWNER" --format json --jq ".projects[] | select(.title == \"$PROJECT_TITLE\") | .number" 2>/dev/null || true)
	if [ -z "$project_number" ]; then
		project_number=$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json --jq '.number')
		echo "[zephyru] project created: $PROJECT_TITLE (#$project_number)"
	else
		echo "[zephyru] project exists: $PROJECT_TITLE (#$project_number)"
	fi
	gh project link "$project_number" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 || true
	while IFS= read -r url; do
		[ -z "$url" ] && continue
		gh project item-add "$project_number" --owner "$OWNER" --url "$url" >/dev/null 2>&1 || true
	done < <(gh issue list --repo "$REPO" --state open --limit 300 --json url --jq '.[].url')
	echo "[zephyru] issues added to project board #$project_number"
else
	echo ""
	echo "[zephyru] Projects v2 board skipped: token is missing the 'project' scope."
	echo "[zephyru] Run once:  gh auth refresh -s project,read:project"
	echo "[zephyru] Then:      bash scripts/setup_github_project.sh"
fi

echo "[zephyru] done. Issues: https://github.com/$REPO/issues"
