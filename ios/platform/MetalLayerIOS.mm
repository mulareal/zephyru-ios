// ZephyrU iOS platform layer
// iOS implementation of CreateMetalLayer() declared in
// src/Cafe/HW/Latte/Renderer/Metal/MetalLayer.h.
//
// The core renderer (MetalLayerHandle) only requires an object that responds to
// nextDrawable/setDrawableSize; on macOS that is an NSView-hosted CAMetalLayer,
// on iOS it is a UIView-hosted CAMetalLayer.

#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>

void* CreateMetalLayer(void* handle, float& scaleX, float& scaleY)
{
	UIView* view = (__bridge UIView*)handle;
	if (!view)
		return nullptr;

	CAMetalLayer* layer = nil;
	if ([view.layer isKindOfClass:[CAMetalLayer class]])
	{
		layer = (CAMetalLayer*)view.layer;
	}
	else
	{
		layer = [CAMetalLayer layer];
		layer.frame = view.bounds;
		[view.layer addSublayer:layer];
	}

	UIScreen* screen = view.window.windowScene.screen ?: view.window.screen;
	const CGFloat scale = screen ? screen.scale : 2.0;
	scaleX = (float)scale;
	scaleY = (float)scale;

	layer.contentsScale = scale;
	layer.framebufferOnly = YES;
	layer.presentsWithTransaction = NO;

	// MetalLayerHandle releases the layer in its destructor, transfer ownership.
	return (__bridge_retained void*)layer;
}
