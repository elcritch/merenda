#include <Cocoa/Cocoa.h>

static const char* nsstr(NSString* s) { return s ? [s UTF8String] : ""; }

@interface Window : NSWindow {
  NSTextField* label1;
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
  [self dumpView:label1 name:@"label1"];
  NSLog(@"[label1] string='%@' bezeled=%d drawsBackground=%d editable=%d selectable=%d alignment=%ld",
      [label1 stringValue], [label1 isBezeled], [label1 drawsBackground], [label1 isEditable], [label1 isSelectable], (long)[label1 alignment]);
}

- (instancetype)init {
  label1 = [[[NSTextField alloc] initWithFrame:NSMakeRect(10, 270, 100, 20)] autorelease];
  [label1 setStringValue:@"label1"];
  [label1 setBezeled:NO];
  [label1 setDrawsBackground:NO];
  [label1 setEditable:NO];
  [label1 setSelectable:NO];
  
  [super initWithContentRect:NSMakeRect(100, 100, 300, 300) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  [self setTitle:@"Label Example"];
  [[self contentView] addSubview:label1];
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
    if (getenv("LABEL_DUMP_LAYOUT_ONCE") != NULL) {
      [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.2];
    }
    [NSApp run];
    return 0;
}
