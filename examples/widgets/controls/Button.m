#include <Cocoa/Cocoa.h>

@interface Window : NSWindow {
  NSButton* button1;
  NSButton* button2;
  NSTextField* label1;
  NSTextField* label2;
  int button1Clicked;
  int button2Clicked;
}

- (instancetype) init;
- (BOOL)windowShouldClose:(id)sender;
- (IBAction) OnButton1Click:(id)sender;
- (IBAction) OnButton2Click:(id)sender;
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
}

- (void)dumpLayout:(NSString*)stage {
  NSRect windowFrame = [self frame];
  NSRect contentRect = [self contentRectForFrameRect:windowFrame];
  NSLog(@"[Window %@] frame=(%.1f,%.1f %.1fx%.1f) contentRect=(%.1f,%.1f %.1fx%.1f)",
      stage,
      windowFrame.origin.x, windowFrame.origin.y, windowFrame.size.width, windowFrame.size.height,
      contentRect.origin.x, contentRect.origin.y, contentRect.size.width, contentRect.size.height);
  [self dumpView:[self contentView] name:@"contentView"];
  [self dumpView:button1 name:@"button1"];
  [self dumpView:button2 name:@"button2"];
  [self dumpView:label1 name:@"label1"];
  [self dumpView:label2 name:@"label2"];
  NSLog(@"[button1] bezelStyle=%ld state=%ld highlighted=%d title='%@' font=%.1f",
      (long)[button1 bezelStyle], (long)[button1 state], [button1 isHighlighted], [button1 title], [[button1 font] pointSize]);
  NSLog(@"[button2] bezelStyle=%ld state=%ld highlighted=%d title='%@' font=%.1f",
      (long)[button2 bezelStyle], (long)[button2 state], [button2 isHighlighted], [button2 title], [[button2 font] pointSize]);
  NSLog(@"[label1] string='%@' bezeled=%d drawsBackground=%d editable=%d font=%.1f alignment=%ld",
      [label1 stringValue], [label1 isBezeled], [label1 drawsBackground], [label1 isEditable], [[[label1 cell] font] pointSize], (long)[label1 alignment]);
  NSLog(@"[label2] string='%@' bezeled=%d drawsBackground=%d editable=%d font=%.1f alignment=%ld",
      [label2 stringValue], [label2 isBezeled], [label2 drawsBackground], [label2 isEditable], [[[label2 cell] font] pointSize], (long)[label2 alignment]);
}

- (instancetype) init {
  button1Clicked = 0;
  button2Clicked = 0;

  button1 = [[[NSButton alloc] initWithFrame:NSMakeRect(50, 225, 90, 25)] autorelease];
  [button1 setTitle:@"button1"];
  [button1 setBezelStyle:NSBezelStyleRounded];
  [button1 setTarget:self];
  [button1 setAction:@selector(OnButton1Click:)];
  [button1 setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];

  button2 = [[[NSButton alloc] initWithFrame:NSMakeRect(50, 125, 200, 75)] autorelease];
  [button2 setTitle:@"button2"];
  [button2 setBezelStyle:NSBezelStyleRegularSquare];
  [button2 setTarget:self];
  [button2 setAction:@selector(OnButton2Click:)];
  [button2 setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  
  label1 = [[NSTextField alloc] initWithFrame:NSMakeRect(50, 80, 200, 20)];
  [label1 setStringValue:@"button1 clicked 0 times"];
  [label1 setBezeled:NO];
  [label1 setDrawsBackground:NO];
  [label1 setEditable:NO];

  label2 = [[NSTextField alloc] initWithFrame:NSMakeRect(50, 50, 200, 20)];
  [label2 setStringValue:@"button2 clicked 0 times"];
  [label2 setBezeled:NO];
  [label2 setDrawsBackground:NO];
  [label2 setEditable:NO];

  [super initWithContentRect:NSMakeRect(100, 100, 300, 300) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  [self setTitle:@"Button example"];
  [[self contentView] addSubview:button1];
  [[self contentView] addSubview:button2];
  [[self contentView] addSubview:label1];
  [[self contentView] addSubview:label2];
  [self setIsVisible:YES];
  [self dumpLayout:@"init"];

  return self;
}

- (BOOL)windowShouldClose:(id)sender {
  [NSApp terminate:sender];
  return YES;
}

- (IBAction) OnButton1Click:(id)sender {
  [label1 setStringValue:[NSString stringWithFormat:@"button1 clicked %d times", ++button1Clicked]];
  [self dumpLayout:@"button1-click"];
}

- (IBAction) OnButton2Click:(id)sender {
  [label2 setStringValue:[NSString stringWithFormat:@"button2 clicked %d times", ++button2Clicked]];
  [self dumpLayout:@"button2-click"];
}
@end

int main(int argc, char *argv[]) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    Window *window = [[Window alloc] init];
    [window makeKeyAndOrderFront:nil];

    [NSApp activateIgnoringOtherApps:YES];
    if (getenv("BUTTON_DUMP_LAYOUT_ONCE") != NULL) {
      [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.2];
    }
    [NSApp run];
    return 0;
}
