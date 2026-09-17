// Native property controls. Bend supplies all selection/property semantics as
// JSON; this adapter only presents controls and returns editor commands.
#if BEND_METAL
#import <AppKit/AppKit.h>

@interface SVGInspector : NSObject
@property(strong) NSPanel* panel;
@property(strong) NSTextField* heading;
@property(strong) NSTextField* hint;
@property(strong) NSTextField* value;
@property(strong) NSPopUpButton* property;
@property(strong) NSPopUpButton* options;
@property(strong) NSButton* apply;
@property(strong) NSButton* remove;
@property(strong) NSDictionary* info;
@property(strong) NSString* previous;
@property(strong) NSMutableArray<NSString*>* commands;
- (void)update:(NSString*)json;
- (NSString*)take;
@end

@implementation SVGInspector
- (NSTextField*)label:(NSString*)text frame:(NSRect)frame {
  NSTextField* field = [NSTextField labelWithString:text];
  field.frame = frame;
  [self.panel.contentView addSubview:field];
  return field;
}
- (NSButton*)button:(NSString*)title frame:(NSRect)frame action:(SEL)action {
  NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
  button.frame = frame;
  [self.panel.contentView addSubview:button];
  return button;
}
- (instancetype)init {
  if (!(self = [super init])) return nil;
  self.commands = [NSMutableArray new];
  NSWindow* drawing = NSApp.mainWindow;
  self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 360, 270)
    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow
    backing:NSBackingStoreBuffered defer:NO];
  self.panel.title = @"Bend SVG — Properties";
  self.panel.releasedWhenClosed = NO;
  self.panel.floatingPanel = YES;
  self.panel.hidesOnDeactivate = NO;
  self.heading = [self label:@"Selected shape — None" frame:NSMakeRect(18, 220, 324, 34)];
  self.heading.identifier = @"selected-shape";
  self.heading.font = [NSFont boldSystemFontOfSize:13];
  self.heading.maximumNumberOfLines = 2;
  [self label:@"Property" frame:NSMakeRect(18, 194, 324, 18)];
  self.property = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 158, 328, 30) pullsDown:NO];
  self.property.identifier = @"property";
  self.property.target = self; self.property.action = @selector(changed:);
  [self.panel.contentView addSubview:self.property];
  self.value = [[NSTextField alloc] initWithFrame:NSMakeRect(18, 119, 238, 26)];
  self.value.identifier = @"value";
  self.value.target = self; self.value.action = @selector(applyValue:);
  [self.panel.contentView addSubview:self.value];
  self.options = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 117, 242, 30) pullsDown:NO];
  self.options.identifier = @"options";
  [self.panel.contentView addSubview:self.options];
  self.apply = [self button:@"Apply" frame:NSMakeRect(264, 117, 80, 30) action:@selector(applyValue:)];
  self.hint = [self label:@"Select a shape to edit its properties." frame:NSMakeRect(18, 66, 324, 42)];
  self.hint.identifier = @"hint";
  self.hint.font = [NSFont systemFontOfSize:11];
  self.hint.textColor = NSColor.secondaryLabelColor;
  self.hint.maximumNumberOfLines = 2;
  [self button:@"Undo" frame:NSMakeRect(14, 20, 88, 30) action:@selector(undo:)];
  self.apply.identifier = @"apply";
  self.remove = [self button:@"Delete" frame:NSMakeRect(108, 20, 88, 30) action:@selector(remove:)];
  [self button:@"Save SVG" frame:NSMakeRect(232, 20, 114, 30) action:@selector(save:)];
  if (drawing != nil) {
    NSRect frame = drawing.frame;
    [self.panel setFrameOrigin:NSMakePoint(NSMaxX(frame) + 12, NSMaxY(frame) - self.panel.frame.size.height)];
    [drawing addChildWindow:self.panel ordered:NSWindowAbove];
  } else {
    [self.panel center];
  }
  [self.panel orderFront:nil];
  return self;
}
- (NSDictionary*)current {
  NSInteger index = self.property.indexOfSelectedItem;
  NSArray* properties = self.info[@"properties"];
  return index >= 0 && index < (NSInteger)properties.count ? properties[index] : nil;
}
- (void)changed:(id)sender {
  NSDictionary* property = self.current;
  NSString* value = property[@"value"] ?: @"";
  NSString* list = property[@"options"] ?: @"";
  BOOL finite = list.length > 0;
  self.value.hidden = finite; self.options.hidden = !finite;
  self.value.stringValue = value;
  self.value.placeholderString = property[@"example"];
  [self.options removeAllItems];
  if (finite) {
    [self.options addItemsWithTitles:[list componentsSeparatedByString:@"|"]];
    if (value.length && [self.options indexOfItemWithTitle:value] < 0) [self.options insertItemWithTitle:value atIndex:0];
    [self.options selectItemWithTitle:value];
  }
  BOOL selected = [self.info[@"selected"] boolValue];
  self.property.enabled = selected; self.value.enabled = selected;
  self.options.enabled = selected; self.apply.enabled = selected; self.remove.enabled = selected;
  NSString* origin = property[@"origin"];
  self.hint.stringValue = !selected ? @"Select a shape to edit its properties." :
    [origin isEqual:@"default"] ? [@"Default: " stringByAppendingString:value] :
    [origin isEqual:@"example"] ? [@"Example: " stringByAppendingString:property[@"example"] ?: @""] :
    [origin isEqual:@"inherited"] ? [@"Inherited value: " stringByAppendingString:value] : @"Current value";
}
- (void)update:(NSString*)json {
  if ([self.previous isEqual:json]) return; // Preserve text being edited while idle.
  NSDictionary* info = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  if (![info isKindOfClass:NSDictionary.class]) return;
  self.previous = json; self.info = info;
  NSString* key = self.property.titleOfSelectedItem ?: @"fill";
  [self.property removeAllItems];
  for (NSDictionary* property in info[@"properties"]) [self.property addItemWithTitle:property[@"key"]];
  [self.property selectItemWithTitle:key];
  NSString* identifier = info[@"id"];
  NSString* label = identifier.length ? [@"#" stringByAppendingString:identifier]
    : [NSString stringWithFormat:@"%@ (no id)", info[@"tag"]];
  self.heading.stringValue = [@"Selected shape — " stringByAppendingString:[info[@"selected"] boolValue] ? label : @"None"];
  [self changed:nil];
}
- (void)applyValue:(id)sender {
  if (![self.info[@"selected"] boolValue]) return;
  NSString* value = self.options.hidden ? self.value.stringValue : self.options.titleOfSelectedItem;
  if ([[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] == 0) return;
  [self.commands addObject:[NSString stringWithFormat:@"set\n%@\n%@", self.current[@"key"], value]];
}
- (void)undo:(id)sender { [self.commands addObject:@"undo"]; }
- (void)remove:(id)sender { if ([self.info[@"selected"] boolValue]) [self.commands addObject:@"delete"]; }
- (void)save:(id)sender { [self.commands addObject:@"save"]; }
- (NSString*)take {
  if (self.commands.count == 0) return @"";
  NSString* command = self.commands.firstObject;
  [self.commands removeObjectAtIndex:0];
  return command;
}
@end

static SVGInspector* svg_inspector;
#endif

Term inspector_step_run(Env e, Term* f, IoWork* work) {
  u64 n = 0;
  char* json = io_cstr(e, f[0], &n);
  Term out;
#if BEND_METAL
  @autoreleasepool {
    NSString* info = [[NSString alloc] initWithBytes:json length:n encoding:NSUTF8StringEncoding];
    if (n == 0) {
      [svg_inspector.panel.parentWindow removeChildWindow:svg_inspector.panel];
      [svg_inspector.panel orderOut:nil];
      svg_inspector = nil;
      out = io_str(e, "", 0);
    } else {
      if (svg_inspector == nil) svg_inspector = [SVGInspector new];
      [svg_inspector update:info];
      NSData* command = [[svg_inspector take] dataUsingEncoding:NSUTF8StringEncoding];
      out = io_str(e, command.bytes, command.length);
    }
  }
#else
  out = io_str(e, "", 0);
#endif
  free(json);
  return out;
}

static void __attribute__((constructor)) inspector_step_use(void) {
  io_eff(CID_INSPECTOR_STEP, inspector_step_run, 0);
}
