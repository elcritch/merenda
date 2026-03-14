#include <Cocoa/Cocoa.h>

static const char* nsstr(NSString* s) { return s ? [s UTF8String] : ""; }

@interface Window : NSWindow {
  NSTextField* textBox1;
  NSTextField* textBox2;
}
- (instancetype)init;
- (BOOL)windowShouldClose:(id)sender;
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
  [self dumpView:textBox1 name:@"textBox1"];
  [self dumpView:textBox2 name:@"textBox2"];
  NSLog(@"[textBox1] string='%@' editable=%d selectable=%d bezeled=%d drawsBackground=%d",
      [textBox1 stringValue], [textBox1 isEditable], [textBox1 isSelectable], [textBox1 isBezeled], [textBox1 drawsBackground]);
  NSLog(@"[textBox2] string='%@' editable=%d selectable=%d bezeled=%d drawsBackground=%d firstResponder=%d",
      [textBox2 stringValue], [textBox2 isEditable], [textBox2 isSelectable], [textBox2 isBezeled], [textBox2 drawsBackground],
      [[self firstResponder] isEqual:textBox2]);
}

- (instancetype)init {
  textBox1 = [[[NSTextField alloc] initWithFrame:NSMakeRect(10, 270, 100, 20)] autorelease];
  [textBox1 setStringValue:@"textBox1"];
  
  textBox2 = [[[NSTextField alloc] initWithFrame:NSMakeRect(10, 230, 100, 20)] autorelease];
  [textBox2 setStringValue:@"textBox2"];
  
  [super initWithContentRect:NSMakeRect(100, 100, 300, 300) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  [self setTitle:@"TextBox Example"];
  [[self contentView] addSubview:textBox1];
  [[self contentView] addSubview:textBox2];
  [self makeFirstResponder:textBox2];
  [self setIsVisible:YES];
  [self dumpLayout:@"init"];
  return self;
}

- (BOOL)windowShouldClose:(id)sender {
  [NSApp terminate:sender];
  return YES;
}
@end

int main(int argc, char *argv[]) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    Window *window = [[Window alloc] init];
    [window makeKeyAndOrderFront:nil];

    [NSApp activateIgnoringOtherApps:YES];
    if (getenv("TEXTBOX_DUMP_LAYOUT_ONCE") != NULL) {
      [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.2];
    }
    [NSApp run];
    return 0;
}
