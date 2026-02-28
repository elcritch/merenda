#include <Cocoa/Cocoa.h>

static const char* nsstr(NSString* s) { return s ? [s UTF8String] : ""; }

@interface Window : NSWindow {
  NSButton* checkBox1;
  NSButton* checkBox2;
  NSButton* checkBox3;
  NSButton* checkBox4;
  NSButton* checkBox5;
}
- (instancetype)init;
- (BOOL)windowShouldClose:(id)sender;
- (IBAction) OnCheckBox1Click:(id)sender;
- (IBAction) OnCheckBox2Click:(id)sender;
- (IBAction) OnCheckBox3Click:(id)sender;
- (IBAction) OnCheckBox4Click:(id)sender;
- (IBAction) OnCheckBox5Click:(id)sender;
- (NSString*) stateToString:(NSControlStateValue)state;
- (void)dumpLayout:(NSString*)stage;
@end

@implementation Window
- (void)dumpView:(NSView*)view name:(NSString*)name {
  NSRect frame = [view frame];
  NSRect bounds = [view bounds];
  NSLog(@"[%@] frame=(%.1f,%.1f %.1fx%.1f) bounds=(%.1f,%.1f %.1fx%.1f) autoresizeMask=0x%lx",
      name,
      frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
      bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height,
      (unsigned long)[view autoresizingMask]);
  printf("[%s] frame=(%.1f,%.1f %.1fx%.1f) bounds=(%.1f,%.1f %.1fx%.1f) autoresizeMask=0x%lx\n",
      nsstr(name),
      frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
      bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height,
      (unsigned long)[view autoresizingMask]);
}

- (void)dumpLayout:(NSString*)stage {
  NSRect windowFrame = [self frame];
  NSRect contentRect = [self contentRectForFrameRect:windowFrame];
  NSLog(@"[Window %@] frame=(%.1f,%.1f %.1fx%.1f) contentRect=(%.1f,%.1f %.1fx%.1f)",
      stage,
      windowFrame.origin.x, windowFrame.origin.y, windowFrame.size.width, windowFrame.size.height,
      contentRect.origin.x, contentRect.origin.y, contentRect.size.width, contentRect.size.height);
  printf("[Window %s] frame=(%.1f,%.1f %.1fx%.1f) contentRect=(%.1f,%.1f %.1fx%.1f)\n",
      nsstr(stage),
      windowFrame.origin.x, windowFrame.origin.y, windowFrame.size.width, windowFrame.size.height,
      contentRect.origin.x, contentRect.origin.y, contentRect.size.width, contentRect.size.height);
  [self dumpView:[self contentView] name:@"contentView"];
  [self dumpView:checkBox1 name:@"checkBox1"];
  [self dumpView:checkBox2 name:@"checkBox2"];
  [self dumpView:checkBox3 name:@"checkBox3"];
  [self dumpView:checkBox4 name:@"checkBox4"];
  [self dumpView:checkBox5 name:@"checkBox5"];
  NSLog(@"[checkBox1] state=%ld mixed=%d bezel=%ld alignment=%ld title='%@'",
      (long)[checkBox1 state], [checkBox1 allowsMixedState], (long)[checkBox1 bezelStyle], (long)[checkBox1 alignment], [checkBox1 title]);
  NSLog(@"[checkBox2] state=%ld mixed=%d bezel=%ld alignment=%ld title='%@'",
      (long)[checkBox2 state], [checkBox2 allowsMixedState], (long)[checkBox2 bezelStyle], (long)[checkBox2 alignment], [checkBox2 title]);
  NSLog(@"[checkBox3] state=%ld mixed=%d bezel=%ld alignment=%ld title='%@'",
      (long)[checkBox3 state], [checkBox3 allowsMixedState], (long)[checkBox3 bezelStyle], (long)[checkBox3 alignment], [checkBox3 title]);
  NSLog(@"[checkBox4] state=%ld mixed=%d bezel=%ld alignment=%ld title='%@'",
      (long)[checkBox4 state], [checkBox4 allowsMixedState], (long)[checkBox4 bezelStyle], (long)[checkBox4 alignment], [checkBox4 title]);
  NSLog(@"[checkBox5] state=%ld mixed=%d bezel=%ld alignment=%ld title='%@'",
      (long)[checkBox5 state], [checkBox5 allowsMixedState], (long)[checkBox5 bezelStyle], (long)[checkBox5 alignment], [checkBox5 title]);
}

- (instancetype)init {
  checkBox1 = [[[NSButton alloc] initWithFrame:NSMakeRect(30, 250, 105, 20)] autorelease];
  [checkBox1 setTitle:@"Unchecked"];
  [checkBox1 setButtonType:NSButtonTypeSwitch];
  [checkBox1 setTarget:self];
  [checkBox1 setAction:@selector(OnCheckBox1Click:)];
  [checkBox1 setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  [checkBox1 setState:NSControlStateValueOff];
  
  checkBox2 = [[[NSButton alloc] initWithFrame:NSMakeRect(30, 220, 105, 20)] autorelease];
  [checkBox2 setTitle:@"Checked"];
  [checkBox2 setButtonType:NSButtonTypeSwitch];
  [checkBox2 setTarget:self];
  [checkBox2 setAction:@selector(OnCheckBox2Click:)];
  [checkBox2 setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  [checkBox2 setState:NSControlStateValueOn];
  
  checkBox3 = [[[NSButton alloc] initWithFrame:NSMakeRect(30, 190, 105, 20)] autorelease];
  [checkBox3 setTitle:@"Mixed"];
  [checkBox3 setAllowsMixedState:YES];
  [checkBox3 setButtonType:NSButtonTypeSwitch];
  [checkBox3 setTarget:self];
  [checkBox3 setAction:@selector(OnCheckBox3Click:)];
  [checkBox3 setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  [checkBox3 setState:NSControlStateValueMixed];

  checkBox4 = [[[NSButton alloc] initWithFrame:NSMakeRect(30, 160, 105, 25)] autorelease];
  [checkBox4 setTitle:@"Checked"];
  [checkBox4 setButtonType:NSButtonTypeOnOff];
  [checkBox4 setBezelStyle:NSBezelStyleRounded];
  [checkBox4 setTarget:self];
  [checkBox4 setAction:@selector(OnCheckBox4Click:)];
  [checkBox4 setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  [checkBox4 setState:NSControlStateValueOn];

  checkBox5 = [[[NSButton alloc] initWithFrame:NSMakeRect(30, 130, 105, 25)] autorelease];
  [checkBox5 setTitle:@"Unchecked"];
  [checkBox5 setButtonType:NSButtonTypeOnOff];
  [checkBox5 setBezelStyle:NSBezelStyleRounded];
  [checkBox5 setTarget:self];
  [checkBox5 setAction:@selector(OnCheckBox5Click:)];
  [checkBox5 setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  [checkBox5 setState:NSControlStateValueOff];

  [super initWithContentRect:NSMakeRect(100, 100, 300, 300) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  [self setTitle:@"CheckBox example"];
  [[self contentView] addSubview:checkBox1];
  [[self contentView] addSubview:checkBox2];
  [[self contentView] addSubview:checkBox3];
  [[self contentView] addSubview:checkBox4];
  [[self contentView] addSubview:checkBox5];
  [self setIsVisible:YES];
  [self dumpLayout:@"init"];
  return self;
}

- (BOOL)windowShouldClose:(id)sender {
  [NSApp terminate:sender];
  return YES;
}

- (IBAction) OnCheckBox1Click:(id)sender {
  [checkBox1 setState:NSControlStateValueOff];
  [checkBox1 setTitle: [self stateToString: [checkBox1 state]]];
  [self dumpLayout:@"checkBox1-click"];
}

- (IBAction) OnCheckBox2Click:(id)sender {
  [checkBox2 setTitle: [self stateToString: [checkBox2 state]]];
  [self dumpLayout:@"checkBox2-click"];
}

- (IBAction) OnCheckBox3Click:(id)sender {
  [checkBox3 setTitle: [self stateToString: [checkBox3 state]]];
  [self dumpLayout:@"checkBox3-click"];
}

- (IBAction) OnCheckBox4Click:(id)sender {
  [checkBox4 setTitle: [self stateToString: [checkBox4 state]]];
  [self dumpLayout:@"checkBox4-click"];
}

- (IBAction) OnCheckBox5Click:(id)sender {
  [checkBox5 setState:NSControlStateValueOff];
  [checkBox5 setTitle: [self stateToString: [checkBox5 state]]];
  [self dumpLayout:@"checkBox5-click"];
}

- (NSString*) stateToString:(NSControlStateValue)state {
  switch (state) {
    case NSControlStateValueOff: return @"Unchecked";
    case NSControlStateValueOn: return @"Checked";
    case NSControlStateValueMixed: return @"Mixed";
  }
  return @"Unchecked";
}
@end

int main(int argc, char *argv[]) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    Window *window = [[Window alloc] init];
    [window makeKeyAndOrderFront:nil];

    [NSApp activateIgnoringOtherApps:YES];
    if (getenv("CHECKBOX_DUMP_LAYOUT_ONCE") != NULL) {
      [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.2];
    }
    [NSApp run];
    return 0;
}
