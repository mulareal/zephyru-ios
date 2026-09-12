# ZephyrU — iOS platform target.
#
# This directory is added by the root CMakeLists.txt when CEMU_IOS=ON. It builds:
#   CemuIOSPlatform  - the iOS implementations of Cemu's platform seams
#                      (WindowSystem, Metal layer, AudioUnit, GameController)
#   ZephyrU          - the iOS application bundle (Objective-C++/UIKit frontend)
#
# The emulator core itself is built from the unmodified upstream target lists
# (CemuCafe/CemuCommon/...), with desktop-only components disabled.

add_library(CemuIOSPlatform STATIC
	platform/WindowSystemIOS.mm
	platform/MetalLayerIOS.mm
	platform/IOSPlatform.mm
	platform/CemuIOSBridge.h
	platform/CemuIOSBridge.mm
	platform/IOSPlatformCallbacks.h
)

target_include_directories(CemuIOSPlatform PUBLIC
	"${CMAKE_CURRENT_SOURCE_DIR}/platform"
	"${CMAKE_SOURCE_DIR}/src"
	"${CMAKE_SOURCE_DIR}/src/gui/interface"
)

target_link_libraries(CemuIOSPlatform PUBLIC
	CemuCommon
	CemuCafe
	CemuComponents
	CemuConfig
	CemuInput
	CemuAudio
	CemuGui
	imguiImpl
)

target_link_libraries(CemuIOSPlatform PUBLIC
	"-framework Foundation"
	"-framework UIKit"
	"-framework CoreGraphics"
	"-framework QuartzCore"
	"-framework Metal"
	"-framework MetalFX"
	"-framework GameController"
	"-framework AudioToolbox"
	"-framework AVFAudio"
)

if (CMAKE_GENERATOR STREQUAL "Xcode")
	set_property(DIRECTORY PROPERTY XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC "YES")
endif()
set_source_files_properties(
	platform/WindowSystemIOS.mm
	platform/MetalLayerIOS.mm
	platform/IOSPlatform.mm
	platform/CemuIOSBridge.mm
	PROPERTIES COMPILE_OPTIONS "-fobjc-arc"
)

# ---------------------------------------------------------------------------
# Application bundle
# ---------------------------------------------------------------------------

set(ZEPHYRU_APP_SOURCES
	app/main.mm
	app/AppDelegate.h
	app/AppDelegate.mm
	app/GameListViewController.h
	app/GameListViewController.mm
	app/EmulatorViewController.h
	app/EmulatorViewController.mm
)

add_executable(ZephyrU MACOSX_BUNDLE ${ZEPHYRU_APP_SOURCES})

set_target_properties(ZephyrU PROPERTIES
	MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/app/Info.plist"
	MACOSX_BUNDLE_GUI_IDENTIFIER "com.zephyru.emulator"
	MACOSX_BUNDLE_BUNDLE_NAME "ZephyrU"
	MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
	MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
	XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.zephyru.emulator"
	XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "26.0"
	XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
	XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
	XCODE_ATTRIBUTE_SWIFT_VERSION "5.0"
	XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/app/ZephyrU.entitlements"
	XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
	XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
)

set_source_files_properties(
	app/main.mm
	app/AppDelegate.mm
	app/GameListViewController.mm
	app/EmulatorViewController.mm
	PROPERTIES COMPILE_OPTIONS "-fobjc-arc"
)

target_compile_definitions(ZephyrU PRIVATE CEMU_IOS=1 HAS_GAMECONTROLLER=1)

target_link_libraries(ZephyrU PRIVATE
	CemuIOSPlatform
	CemuCafe
	CemuCommon
	CemuComponents
	CemuConfig
	CemuInput
	CemuAudio
	CemuGui
	CemuUtil
	imguiImpl
	"-framework UniformTypeIdentifiers"
)

# Bundle Cemu's runtime data (game profiles, graphic packs, resources) so the
# emulator finds them at the same relative location as on desktop.
if (EXISTS "${CMAKE_SOURCE_DIR}/bin")
	foreach(folder gameProfiles graphicPacks resources)
		if (EXISTS "${CMAKE_SOURCE_DIR}/bin/${folder}")
			add_custom_command(TARGET ZephyrU POST_BUILD
				COMMAND ${CMAKE_COMMAND} -E copy_directory
					"${CMAKE_SOURCE_DIR}/bin/${folder}"
					"$<TARGET_BUNDLE_DIR:ZephyrU>/SharedSupport/${folder}"
			)
		endif()
	endforeach()
endif()
