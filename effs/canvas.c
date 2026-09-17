// Native pixel presentation and input only. SVG rendering stays in Bend.
#if BEND_METAL
#import <AppKit/AppKit.h>
@interface SVGCanvas : NSView <NSWindowDelegate>
@property(strong) NSMutableArray<NSString*>* commands;
@property(strong) NSData* pixels;
@property uint32_t pixelWidth, pixelHeight, requestedWidth, requestedHeight;
@property BOOL closing;
@end
@implementation SVGCanvas
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSSize)pixelSize {
  NSSize size = [self convertSizeToBacking:self.bounds.size];
  return NSMakeSize(MAX(1, MIN(4096, round(size.width))), MAX(1, MIN(4096, round(size.height))));
}
- (void)drawRect:(NSRect)rect {
  [NSColor.whiteColor setFill]; NSRectFill(rect);
  NSSize size = [self pixelSize];
  if (!self.pixels || size.width != self.pixelWidth || size.height != self.pixelHeight) return;
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)self.pixels);
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGImageRef image = CGImageCreate(self.pixelWidth, self.pixelHeight, 8, 32,
    self.pixelWidth * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast, provider, NULL, false, kCGRenderingIntentDefault);
  CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
  CGContextSaveGState(ctx);
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  NSSize logical = [self convertSizeFromBacking:size];
  CGContextTranslateCTM(ctx, 0, logical.height); CGContextScaleCTM(ctx, 1, -1);
  CGContextDrawImage(ctx, CGRectMake(0, 0, logical.width, logical.height), image);
  CGContextRestoreGState(ctx);
  CGImageRelease(image); CGColorSpaceRelease(space); CGDataProviderRelease(provider);
}
- (void)windowDidResize:(NSNotification*)note { self.needsDisplay = YES; }
- (void)windowDidChangeBackingProperties:(NSNotification*)note {
  CGFloat scale = self.window.backingScaleFactor;
  self.window.contentMaxSize = NSMakeSize(4096/scale, 4096/scale);
  self.needsDisplay = YES;
}
- (BOOL)windowShouldClose:(NSWindow*)window { self.closing = YES; return NO; }
- (void)keyDown:(NSEvent*)event {
  NSString* chars = event.charactersIgnoringModifiers.lowercaseString;
  if (chars.length) [self.commands addObject:[NSString stringWithFormat:@"key\n%u", [chars characterAtIndex:0]]];
}
- (void)pointer:(NSEvent*)event command:(NSString*)command {
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  // Backing point conversion can flip the origin; scale view-local distances.
  CGFloat scale = self.window.backingScaleFactor;
  point.x *= scale; point.y *= scale;
  NSSize size = [self pixelSize];
  NSString* text = [NSString stringWithFormat:@"%@\n%u %u", command,
    (unsigned)MAX(0, MIN(size.width-1, floor(point.x))), (unsigned)MAX(0, MIN(size.height-1, floor(point.y)))];
  if ([command isEqual:@"move"] && [self.commands.lastObject hasPrefix:@"move\n"]) [self.commands removeLastObject];
  [self.commands addObject:text];
}
- (void)mouseDown:(NSEvent*)event { [self.window makeFirstResponder:self]; [self pointer:event command:@"down"]; }
- (void)mouseDragged:(NSEvent*)event { [self pointer:event command:@"move"]; }
- (void)mouseUp:(NSEvent*)event { [self pointer:event command:@"move"]; [self.commands addObject:@"up"]; }
@end
static NSWindow* svg_canvas_window;
static SVGCanvas* svg_canvas_view;
static void svg_canvas_open(void) {
  if (svg_canvas_window) return;
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
  [NSApp finishLaunching];
  NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 512, 512)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
    backing:NSBackingStoreBuffered defer:NO];
  window.title = @"Bend SVG - F fit / +/- zoom / HJKL pan / Z undo";
  window.releasedWhenClosed = NO;
  window.contentMinSize = NSMakeSize(128, 128);
  window.contentMaxSize = NSMakeSize(4096/window.backingScaleFactor, 4096/window.backingScaleFactor);
  SVGCanvas* view = [[SVGCanvas alloc] initWithFrame:window.contentLayoutRect];
  view.commands = [NSMutableArray array];
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  window.contentView = view; window.delegate = view;
  svg_canvas_window = window; svg_canvas_view = view;
  [window center]; [window makeKeyAndOrderFront:nil]; [window makeFirstResponder:view];
  [NSApp activateIgnoringOtherApps:YES];
}
#endif

Term canvas_present_run(Env e, Term* f, IoWork* work) {
#if BEND_METAL
  @autoreleasepool {
    svg_canvas_open();
    u32 w = (u32)f[1], h = (u32)f[2];
    if (w && h && w <= 4096 && h <= 4096) {
      NSMutableData* data = [NSMutableData dataWithLength:(NSUInteger)w*h*4];
      uint8_t* bytes = data.mutableBytes;
      Loc loc = term_peek(e, f[0]);
      for (u32 i = 0; i < w*h; i++) {
        u32 pixel = (u32)blk_read(e.mem, 0, loc, i);
        bytes[4*i] = pixel >> 16; bytes[4*i+1] = pixel >> 8; bytes[4*i+2] = pixel; bytes[4*i+3] = 255;
      }
      svg_canvas_view.pixels = data;
      svg_canvas_view.pixelWidth = w; svg_canvas_view.pixelHeight = h;
      svg_canvas_view.needsDisplay = YES;
      [svg_canvas_view displayIfNeeded];
    }
  }
#endif
  term_drop(e, f[0]);
  return term_pak(CID_UNIT, 0);
}
Term canvas_poll_run(Env e, Term* f, IoWork* work) {
#if BEND_METAL
  @autoreleasepool {
    svg_canvas_open();
    NSEvent* event;
    while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
    [NSApp updateWindows];
    SVGCanvas* view = svg_canvas_view;
    if (view.closing) { [svg_canvas_window orderOut:nil]; return io_str(e, "close", 5); }
    NSSize size = [view pixelSize];
    NSString* text = @"";
    if (size.width != view.requestedWidth || size.height != view.requestedHeight) {
      view.requestedWidth = size.width; view.requestedHeight = size.height;
      [view.commands removeAllObjects];
      text = [NSString stringWithFormat:@"resize\n%u %u", view.requestedWidth, view.requestedHeight];
    } else if (view.commands.count) {
      text = view.commands.firstObject; [view.commands removeObjectAtIndex:0];
    } else {
      // Let AppKit timers and controls run while idle, without repainting.
      [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.008]];
    }
    return io_str(e, text.UTF8String, [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
  }
#else
  return io_str(e, "close", 5);
#endif
}
static void __attribute__((constructor)) canvas_use(void) {
  io_eff(CID_CANVAS_PRESENT, canvas_present_run, 0);
  io_eff(CID_CANVAS_POLL, canvas_poll_run, 0);
}
