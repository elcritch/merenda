#include <Cocoa/Cocoa.h>
#include <stdlib.h>

@interface Window : NSWindow  {
  NSComboBox* comboBox1;
  NSComboBox* comboBox2;
}
- (instancetype)init;
- (void)dumpLayout:(NSString *)stage;
- (void)dumpAndTriggerForPorting;
- (BOOL)windowShouldClose:(id)sender;
@end

@implementation Window
- (int)intBool:(BOOL)flag {
  return flag ? 1 : 0;
}

- (void)dumpComboBox:(NSComboBox *)comboBox name:(const char *)name {
  NSRect frame = [comboBox frame];
  NSRect bounds = [comboBox bounds];
  NSLog(@"[%s] frame=(%.1f,%.1f %.1fx%.1f) bounds=(%.1f,%.1f %.1fx%.1f) autoresizeMask=0x%02lx",
    name,
    frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
    bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height,
    (unsigned long)[comboBox autoresizingMask]);
  NSLog(@"[%s] editable=%d selected=%ld numberOfItems=%ld string='%@'",
    name,
    [self intBool:[comboBox isEditable]],
    (long)[comboBox indexOfSelectedItem],
    (long)[comboBox numberOfItems],
    [comboBox stringValue]);
}

- (void)dumpLayout:(NSString *)stage {
  NSRect frame = [self frame];
  NSRect contentRect = [self contentRectForFrameRect:frame];
  NSView *content = [self contentView];
  NSRect contentFrame = [content frame];
  NSRect contentBounds = [content bounds];
  NSLog(@"[Window %@] frame=(%.1f,%.1f %.1fx%.1f) contentRect=(%.1f,%.1f %.1fx%.1f)",
    stage,
    frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
    contentRect.origin.x, contentRect.origin.y, contentRect.size.width, contentRect.size.height);
  NSLog(@"[contentView] frame=(%.1f,%.1f %.1fx%.1f) bounds=(%.1f,%.1f %.1fx%.1f) autoresizeMask=0x%02lx",
    contentFrame.origin.x, contentFrame.origin.y, contentFrame.size.width, contentFrame.size.height,
    contentBounds.origin.x, contentBounds.origin.y, contentBounds.size.width, contentBounds.size.height,
    (unsigned long)[content autoresizingMask]);
  [self dumpComboBox:comboBox1 name:"comboBox1"];
  [self dumpComboBox:comboBox2 name:"comboBox2"];
}

- (instancetype)init {
  self = [super initWithContentRect:NSMakeRect(100, 100, 300, 300) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
  if (self == nil) {
    return nil;
  }

  comboBox1 = [[[NSComboBox alloc] initWithFrame:NSMakeRect(10, 260, 121, 26)] autorelease];
  [comboBox1 addItemWithObjectValue:@"item1"];
  [comboBox1 addItemWithObjectValue:@"item2"];
  [comboBox1 addItemWithObjectValue:@"item3"];
  [comboBox1 setTarget:self];
  [comboBox1 setAction:@selector(OnComboBox1SelectedItemChange:)];
  //[[comboBox1 delegate] comboBoxSelectionIsChanging: ];
  //[comboBox1 setDelegate:self];
  [comboBox1 selectItemAtIndex:1];
  
  comboBox2 = [[[NSComboBox alloc] initWithFrame:NSMakeRect(10, 220, 121, 26)] autorelease];
  [comboBox2 setEditable:false];
  [comboBox2 addItemWithObjectValue:@"item1"];
  [comboBox2 addItemWithObjectValue:@"item2"];
  [comboBox2 addItemWithObjectValue:@"item3"];
  [comboBox2 setTarget:self];
  //[comboBox2 setAction:@selector(OnComboBox2SelectedItemChange)];
  [comboBox2 selectItemAtIndex:1];

  [self setTitle:@"ComboBox Example"];
  [[self contentView] addSubview:comboBox1];
  [[self contentView] addSubview:comboBox2];
  [self setIsVisible:YES];
  [self dumpLayout:@"init"];
  return self;
}

- (BOOL)windowShouldClose:(id)sender {
  [NSApp terminate:sender];
  return YES;
}

- (IBAction) OnComboBox1SelectedItemChange:(id)sender {
  [comboBox2 selectItemAtIndex:[comboBox1 indexOfSelectedItem]];
  [self dumpLayout:@"comboBox1-change"];
}

- (IBAction) OnComboBox2SelectedItemChange:(id)sender {
  [comboBox1 selectItemAtIndex:[comboBox2 indexOfSelectedItem]];
  [self dumpLayout:@"comboBox2-change"];
}

- (void)dumpAndTriggerForPorting {
  [self dumpLayout:@"post-front"];
  [self OnComboBox1SelectedItemChange:self];
  [NSApp terminate:self];
}

- (void)OnComboBox1SelectionIsChanging:(NSNotification *)notification {
  
}
- (void)comboBoxSelectionIsChanging:(NSNotification *)notification {
  
}

@end

int main(int argc, char *argv[]) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    Window *window = [[Window alloc] init];
    [window makeKeyAndOrderFront:nil];

    if (getenv("NUTELLA_COMBOBOX_EXIT_AFTER_DUMP")) {
      [NSApp activateIgnoringOtherApps:YES];
      [window performSelector:@selector(dumpAndTriggerForPorting) withObject:nil afterDelay:0.05];
      [NSApp run];
      return 0;
    }

    [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
    return 0;
}
