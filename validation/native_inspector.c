// Exercise the actual AppKit controls and native Bend reducer in this test
// process. Mouse events go through the real canvas view, never global input.
#if BEND_METAL
#import <AppKit/AppKit.h>
static int inspector_test_stage, inspector_test_ticks;
static void inspector_test_assert(BOOL ok, const char* message) {
  if (!ok) { fprintf(stderr, "FAIL native inspector: %s\n", message); exit(1); }
}
static NSView* inspector_test_view(NSView* root, NSString* identifier) {
  for (NSView* v in root.subviews) if ([v.identifier isEqual:identifier]) return v;
  return nil;
}
static NSButton* inspector_test_button(NSView* root, NSString* title) {
  for (NSView* v in root.subviews) if ([v isKindOfClass:NSButton.class] && [((NSButton*)v).title isEqual:title]) return (NSButton*)v;
  return nil;
}
static void inspector_test_select(NSPopUpButton* property, NSString* key) {
  [property selectItemWithTitle:key];
  [NSApp sendAction:property.action to:property.target from:property];
}
static void inspector_test_click(NSWindow* drawing, CGFloat x, CGFloat y) {
  NSSize size = drawing.contentView.bounds.size;
  CGFloat fit = MIN(size.width, size.height)/256;
  x = (size.width-256*fit)/2+x*fit; y = (size.height-256*fit)/2+y*fit;
  for (int i = 0; i < 2; i++) {
    NSEvent* event = [NSEvent mouseEventWithType:i ? NSEventTypeLeftMouseUp : NSEventTypeLeftMouseDown
      location:NSMakePoint(x, size.height-y) modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
      windowNumber:drawing.windowNumber context:nil eventNumber:1 clickCount:1 pressure:i ? 0 : 1];
    if (i) [drawing.contentView mouseUp:event]; else [drawing.contentView mouseDown:event];
  }
}
static void inspector_test_drag(NSWindow* drawing) {
  NSSize size = drawing.contentView.bounds.size;
  CGFloat fit = MIN(size.width, size.height)/256;
  for (int i = 0; i < 3; i++) {
    CGFloat x = (size.width-256*fit)/2+(i ? 28 : 20)*fit;
    CGFloat y = (size.height-256*fit)/2+(i ? 24 : 20)*fit;
    NSEvent* event = [NSEvent mouseEventWithType:i == 0 ? NSEventTypeLeftMouseDown : i == 1 ? NSEventTypeLeftMouseDragged : NSEventTypeLeftMouseUp
      location:NSMakePoint(x, size.height-y) modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
      windowNumber:drawing.windowNumber context:nil eventNumber:1 clickCount:1 pressure:i == 2 ? 0 : 1];
    if (i == 0) [drawing.contentView mouseDown:event];
    else if (i == 1) [drawing.contentView mouseDragged:event];
    else [drawing.contentView mouseUp:event];
  }
}
static BOOL inspector_test_value(NSPopUpButton* property, NSString* key, NSString* value) {
  NSDictionary* info = [property.target valueForKey:@"info"];
  for (NSDictionary* p in info[@"properties"]) if ([p[@"key"] isEqual:key]) return [p[@"value"] isEqual:value];
  return NO;
}
static void inspector_test_tick(NSTimer* timer) {
  inspector_test_assert(++inspector_test_ticks < 600, "timed out");
  NSWindow* panel = nil; NSWindow* drawing = nil;
  for (NSWindow* window in NSApp.windows) {
    if ([window.title isEqual:@"Bend SVG — Properties"]) panel = window;
    else if ([window.title hasPrefix:@"Bend SVG -"]) drawing = window;
  }
  if (!panel || !drawing) return;
  NSView* root = panel.contentView;
  NSTextField* heading = (NSTextField*)inspector_test_view(root, @"selected-shape");
  NSTextField* value = (NSTextField*)inspector_test_view(root, @"value");
  NSTextField* hint = (NSTextField*)inspector_test_view(root, @"hint");
  NSPopUpButton* property = (NSPopUpButton*)inspector_test_view(root, @"property");
  NSPopUpButton* options = (NSPopUpButton*)inspector_test_view(root, @"options");
  NSButton* apply = inspector_test_button(root, @"Apply");
  NSString* output = [NSString stringWithUTF8String:getenv("SVG_OUTPUT")];
  switch (inspector_test_stage) {
    case 0: {
      static BOOL resized = NO;
      if (!resized) {
        inspector_test_assert((drawing.styleMask & NSWindowStyleMaskResizable) != 0, "resizable window");
        [drawing setContentSize:NSMakeSize(640, 384)]; resized = YES; return;
      }
      NSSize backing = [drawing.contentView convertSizeToBacking:drawing.contentView.bounds.size];
      if ([[drawing.contentView valueForKey:@"pixelWidth"] unsignedIntValue] != (unsigned)backing.width ||
          [[drawing.contentView valueForKey:@"pixelHeight"] unsignedIntValue] != (unsigned)backing.height) return;
      inspector_test_assert([heading.stringValue containsString:@"None"] && !apply.enabled, "initial selection");
      NSBitmapImageRep* bitmap = [drawing.contentView bitmapImageRepForCachingDisplayInRect:drawing.contentView.bounds];
      [drawing.contentView cacheDisplayInRect:drawing.contentView.bounds toBitmapImageRep:bitmap];
      CGFloat scale = drawing.backingScaleFactor;
      // Compare raw capture samples; converting a display profile to sRGB
      // changes RGB numbers even for this exact blue source pixel.
      NSUInteger sample[4] = {0};
      [bitmap getPixel:sample atX:158*scale y:30*scale];
      inspector_test_assert(sample[0] == 0 && sample[1] == 0 && sample[2] == 255, "displayed pixels and mouse coordinates align");
      inspector_test_click(drawing, 20, 20); inspector_test_stage++; break;
    }
    case 1:
      if (![heading.stringValue containsString:@"#box"]) return;
      inspector_test_assert([value.stringValue isEqual:@"blue"], "inline fill");
      inspector_test_select(property, @"stroke");
      inspector_test_assert([value.stringValue isEqual:@"red"] && [hint.stringValue containsString:@"Inherited"], "inherited stroke");
      inspector_test_select(property, @"stroke-width");
      inspector_test_assert([value.stringValue isEqual:@"3"], "stylesheet value");
      inspector_test_select(property, @"stroke-linecap");
      inspector_test_assert(value.hidden && !options.hidden && [options.titleOfSelectedItem isEqual:@"butt"], "default dropdown");
      [options selectItemWithTitle:@"round"]; [apply performClick:nil]; inspector_test_stage++; break;
    case 2:
      if (!inspector_test_value(property, @"stroke-linecap", @"round")) return;
      [inspector_test_button(root, @"Save SVG") performClick:nil]; inspector_test_stage++; break;
    case 3: {
      NSString* saved = [NSString stringWithContentsOfFile:output encoding:NSUTF8StringEncoding error:nil];
      if (![saved containsString:@"stroke-linecap:round"]) return;
      [inspector_test_button(root, @"Undo") performClick:nil]; inspector_test_stage++; break;
    }
    case 4:
      if (!inspector_test_value(property, @"stroke-linecap", @"butt")) return;
      inspector_test_assert([options.titleOfSelectedItem isEqual:@"butt"], "undo refreshes dropdown");
      inspector_test_select(property, @"fill"); value.stringValue = @"purple";
      [apply performClick:nil]; inspector_test_stage++; break;
    case 5:
      if (!inspector_test_value(property, @"fill", @"purple")) return;
      inspector_test_click(drawing, 120, 20); inspector_test_stage++; break;
    case 6:
      if (![heading.stringValue containsString:@"rect (no id)"]) return;
      inspector_test_assert([value.stringValue isEqual:@"orange"], "selection refreshes inherited fill");
      inspector_test_select(property, @"textLength");
      inspector_test_assert(value.stringValue.length == 0 && [value.placeholderString isEqual:@"100"], "example placeholder");
      for (NSString* key in @[@"paint-order", @"stroke-linejoin", @"vector-effect", @"mask-mode", @"fill-rule", @"preserveAspectRatio", @"image-rendering", @"lengthAdjust", @"font-style", @"text-anchor"]) {
        inspector_test_select(property, key);
        inspector_test_assert(!options.hidden && options.numberOfItems > 1, "finite options");
      }
      [inspector_test_button(root, @"Delete") performClick:nil]; inspector_test_stage++; break;
    case 7:
      if (![heading.stringValue containsString:@"None"]) return;
      inspector_test_assert(!apply.enabled && !options.enabled, "deleted selection disabled");
      [inspector_test_button(root, @"Undo") performClick:nil]; inspector_test_stage++; break;
    case 8: {
      if (![heading.stringValue containsString:@"rect (no id)"]) return;
      inspector_test_assert(apply.enabled, "undo restores selection");
      inspector_test_select(property, @"fill");
      NSBitmapImageRep* bitmap = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
      [root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];
      [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[output stringByAppendingString:@".panel.png"] atomically:YES];
      inspector_test_drag(drawing); inspector_test_stage++; break;
    }
    case 9:
      if (![heading.stringValue containsString:@"#box"]) return;
      [inspector_test_button(root, @"Save SVG") performClick:nil]; inspector_test_stage++; break;
    case 10: {
      NSString* saved = [NSString stringWithContentsOfFile:output encoding:NSUTF8StringEncoding error:nil];
      NSRange start = [saved rangeOfString:@"transform:matrix("];
      if (start.location == NSNotFound) return;
      NSString* matrix = [[[saved substringFromIndex:NSMaxRange(start)] componentsSeparatedByString:@")"] firstObject];
      NSArray* values = [matrix componentsSeparatedByString:@","];
      inspector_test_assert(values.count == 6, "saved matrix components");
      const double expected[] = {1, 0, 0, 1, 8, 4};
      for (int i = 0; i < 6; i++) inspector_test_assert(fabs([values[i] doubleValue]-expected[i]) < 0.000001, "drag after resize saved geometry");
      [@"PASS" writeToFile:[output stringByAppendingString:@".test"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
      puts("PASS native inspector: rectangular backing-pixel resize, drag/save, selection IDs, inherited/stylesheet values, defaults, examples, dropdown editing, save, delete and undo");
      fflush(stdout); [timer invalidate];
      [drawing.delegate windowShouldClose:drawing];
      break;
    }
  }
}
#endif
Term test_start_run(Env e, Term* f, IoWork* work) {
#if BEND_METAL
  [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer* timer) { inspector_test_tick(timer); }];
#endif
  return term_pak(CID_UNIT, 0);
}
static void __attribute__((constructor)) test_start_use(void) { io_eff(CID_TEST_START, test_start_run, 0); }
