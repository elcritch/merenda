import ./runtime

objcImpl:
  type NSTrackingArea* = object of NSObject
    xRect: NSRect
    xOptions {.get: options.}: set[NSTrackingAreaOptions]
    xOwner: ID
    xUserData: pointer
    xRetainUserData: bool

    #// NSWindow needs this. It's maintained when areas are collected for the window.
    xView: NSView
    #// NSWindow needs this. It's maintained when areas are collected for the window.
    xRectInWindow: NSRect
    #// _mouseInside is a marker handled by NSWindow.
    xMouseInside: bool
    #// Instead of sending events, show the NSToolTipWindow.
    #// The text for the tooltip is fetched from owner.
    xIsToolTip: bool
    # Needed for compatibility with legacy cursorRects. If YES, this area will be
    # discarded by -[NSView discardCursorRects] (and -[NSWindow discardCursorRects]).
    xLegacy {.get: isLegacy.}: bool

proc new*(t: typedesc[NSTrackingArea]): NSTrackingArea =
  var allocated = NSFormatter.alloc()
  result = initOwned(move(allocated))
