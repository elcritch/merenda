import std/math

import ./runtime
import ./views
import ./clipviews
import ./scrollers
import ./rulerviews

var rulerViewImplClass: ObjcClass = nil

proc insetByBorder(bounds: NSRect, borderType: NSBorderType): NSRect =
  case borderType
  of NSNoBorder:
    bounds
  of NSLineBorder, NSBezelBorder:
    nsRect(
      bounds.origin.x + 1.0,
      bounds.origin.y + 1.0,
      max(bounds.size.width - 2.0, 0.0),
      max(bounds.size.height - 2.0, 0.0),
    )
  of NSGrooveBorder:
    nsRect(
      bounds.origin.x + 2.0,
      bounds.origin.y + 2.0,
      max(bounds.size.width - 4.0, 0.0),
      max(bounds.size.height - 4.0, 0.0),
    )

template sendViewNoArg(receiver: NSView, selectorName: static[string]): NSView =
  block:
    if receiver.isNil:
      NSView(value: nil)
    else:
      let receiverObj = asRetainedType[NSObject](receiver.value)
      if not receiverObj.respondsToSelector(selectorName):
        NSView(value: nil)
      else:
        let selector = getSelector(selectorName)
        let raw = cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(
          receiver.value, selector
        )
        ownFromId[NSView](raw)

proc currentRulerClass(): ObjcClass =
  if rulerViewImplClass.isNil:
    rulerViewImplClass = getClass(NSRulerView)
  rulerViewImplClass

proc newRulerView(
    scrollView: NSScrollView, orientation: NSRulerOrientation
): NSRulerView =
  let cls = currentRulerClass()
  if cls.isNil:
    return NSRulerView(value: nil)
  var allocated = asTypeRaw[NSRulerView](alloc(cls))
  result = allocated.initWithScrollView(scrollView, orientation)
  allocated.value = nil

objcImpl:
  type NSScrollView* = object of NSView
    xClipView: NSClipView
    xHeaderClipView: NSClipView
    xCornerView: NSView
    xVerticalScroller: NSScroller
    xHorizontalScroller: NSScroller
    xHorizontalRuler: NSRulerView
    xVerticalRuler: NSRulerView
    xBackgroundColor: NSColor
    xVerticalLineScroll: float32
    xVerticalPageScroll: float32
    xHorizontalLineScroll: float32
    xHorizontalPageScroll: float32
    xBorderType: NSBorderType
    xDrawsBackground: bool
    xHasVerticalScroller: bool
    xHasHorizontalScroller: bool
    xHasHorizontalRuler: bool
    xHasVerticalRuler: bool
    xRulersVisible: bool
    xScrollsDynamically: bool
    xAutohidesScrollers: bool
    xDocumentCursor: NSCursor

  method insetBounds*(self: NSScrollView): NSRect =
    insetByBorder(self.bounds(), self.xBorderType)

  method headerViewInternal*(self: NSScrollView): NSView =
    sendViewNoArg(self.documentView(), "headerView")

  method cornerViewInternal*(self: NSScrollView): NSView =
    sendViewNoArg(self.documentView(), "cornerView")

  method headerClipViewFrame*(self: NSScrollView): NSRect =
    let headerView = self.headerViewInternal()
    if headerView.isNil:
      return nsRect(0.0, 0.0, 0.0, 0.0)
    var result = self.insetBounds()
    result.size.height = headerView.bounds().size.height
    result.size.width = max(result.size.width - NSScroller.scrollerWidth(), 0.0)
    result

  method cornerViewFrame*(self: NSScrollView): NSRect =
    let headerView = self.headerViewInternal()
    if headerView.isNil:
      return nsRect(0.0, 0.0, 0.0, 0.0)
    let bounds = self.insetBounds()
    nsRect(
      bounds.origin.x + bounds.size.width - NSScroller.scrollerWidth(),
      bounds.origin.y,
      NSScroller.scrollerWidth(),
      headerView.bounds().size.height,
    )

  method horizontalRulerFrame*(self: NSScrollView): NSRect =
    var result = self.insetBounds()
    result.size.height =
      if self.xHorizontalRuler.isNil:
        0.0
      else:
        self.xHorizontalRuler.requiredThickness()
    result

  method verticalRulerFrame*(self: NSScrollView): NSRect =
    var result = self.insetBounds()
    result.size.width =
      if self.xVerticalRuler.isNil:
        0.0
      else:
        self.xVerticalRuler.requiredThickness()
    if self.xRulersVisible and self.xHasHorizontalRuler and
        (not self.xHorizontalRuler.isNil):
      let h = self.xHorizontalRuler.requiredThickness()
      result.origin.y += h
      result.size.height = max(result.size.height - h, 0.0)
    result

  method clipViewFrame*(self: NSScrollView): NSRect =
    let bounds = self.insetBounds()
    var result =
      nsRect(bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height)
    if self.xHasVerticalScroller and (not self.xVerticalScroller.isNil) and
        (not self.xVerticalScroller.isHidden()):
      result.size.width = max(result.size.width - NSScroller.scrollerWidth(), 0.0)
    if self.xRulersVisible and self.xHasVerticalRuler:
      let rulerFrame = self.verticalRulerFrame()
      result.origin.x += rulerFrame.size.width
      result.size.width = max(result.size.width - rulerFrame.size.width, 0.0)

    if self.xHasHorizontalScroller and (not self.xHorizontalScroller.isNil) and
        (not self.xHorizontalScroller.isHidden()):
      result.size.height = max(result.size.height - NSScroller.scrollerWidth(), 0.0)
    if self.xRulersVisible and self.xHasHorizontalRuler:
      let rulerFrame = self.horizontalRulerFrame()
      result.origin.y += rulerFrame.size.height
      result.size.height = max(result.size.height - rulerFrame.size.height, 0.0)

    if not self.headerViewInternal().isNil:
      let headerFrame = self.headerClipViewFrame()
      result.origin.y += headerFrame.size.height
      result.size.height = max(result.size.height - headerFrame.size.height, 0.0)
    result

  method verticalScrollerFrame*(self: NSScrollView): NSRect =
    let bounds = self.insetBounds()
    var result = nsRect(
      bounds.origin.x + bounds.size.width - NSScroller.scrollerWidth(),
      bounds.origin.y,
      NSScroller.scrollerWidth(),
      bounds.size.height,
    )
    if self.xHasHorizontalScroller and (not self.xHorizontalScroller.isNil) and
        (not self.xHorizontalScroller.isHidden()):
      result.size.height = max(result.size.height - NSScroller.scrollerWidth(), 0.0)
    if not self.headerViewInternal().isNil:
      let headerFrame = self.headerClipViewFrame()
      result.origin.y += headerFrame.size.height
      result.size.height = max(result.size.height - headerFrame.size.height, 0.0)
    if self.xRulersVisible and self.xHasHorizontalRuler and
        (not self.xHorizontalRuler.isNil):
      let thickness = self.xHorizontalRuler.requiredThickness()
      result.origin.y += thickness
      result.size.height = max(result.size.height - thickness, 0.0)
    result

  method horizontalScrollerFrame*(self: NSScrollView): NSRect =
    let bounds = self.insetBounds()
    var result = nsRect(
      bounds.origin.x,
      bounds.origin.y + bounds.size.height - NSScroller.scrollerWidth(),
      bounds.size.width,
      NSScroller.scrollerWidth(),
    )
    if self.xHasVerticalScroller and (not self.xVerticalScroller.isNil) and
        (not self.xVerticalScroller.isHidden()):
      result.size.width = max(result.size.width - NSScroller.scrollerWidth(), 0.0)
    if self.xRulersVisible and self.xHasVerticalRuler and (
      not self.xVerticalRuler.isNil
    ):
      let thickness = self.xVerticalRuler.requiredThickness()
      result.origin.x += thickness
      result.size.width = max(result.size.width - thickness, 0.0)
    result

  method createVerticalScrollerIfNeeded*(self: NSScrollView) =
    if not self.xVerticalScroller.isNil:
      return
    let frame = self.verticalScrollerFrame()
    var allocated = NSScroller.alloc()
    var scroller = allocated.initWithFrame(
      frame.origin.x.float32, frame.origin.y.float32, frame.size.width.float32,
      frame.size.height.float32,
    )
    allocated.value = nil
    scroller.setAutoresizingMask(NSViewMinXMargin or NSViewHeightSizable)
    scroller.setTarget(ID(value: self.value))
    scroller.setAction(getSelector("verticalScroll:"))
    self.xVerticalScroller = scroller

  method createHorizontalScrollerIfNeeded*(self: NSScrollView) =
    if not self.xHorizontalScroller.isNil:
      return
    let frame = self.horizontalScrollerFrame()
    var allocated = NSScroller.alloc()
    var scroller = allocated.initWithFrame(
      frame.origin.x.float32, frame.origin.y.float32, frame.size.width.float32,
      frame.size.height.float32,
    )
    allocated.value = nil
    scroller.setAutoresizingMask(NSViewMaxYMargin or NSViewWidthSizable)
    scroller.setTarget(ID(value: self.value))
    scroller.setAction(getSelector("horizontalScroll:"))
    self.xHorizontalScroller = scroller

  method initWithFrame*(
      self: var NSScrollView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSScrollView =
    result =
      asTypeRaw[NSScrollView](callSuperIdFrom(NSScrollView, self, getSelector("init")))
    if result.isNil:
      return
    result.setFrame(
      x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0)
    )
    result.xClipView = NSClipView(value: nil)
    result.xHeaderClipView = NSClipView(value: nil)
    result.xCornerView = NSView(value: nil)
    result.xVerticalScroller = NSScroller(value: nil)
    result.xHorizontalScroller = NSScroller(value: nil)
    result.xHorizontalRuler = NSRulerView(value: nil)
    result.xVerticalRuler = NSRulerView(value: nil)
    result.xBackgroundColor = nsColor(1.0, 1.0, 1.0, 1.0)
    result.xVerticalLineScroll = 1.0
    result.xVerticalPageScroll = 10.0
    result.xHorizontalLineScroll = 1.0
    result.xHorizontalPageScroll = 10.0
    result.xBorderType = NSNoBorder
    result.xDrawsBackground = true
    result.xHasVerticalScroller = false
    result.xHasHorizontalScroller = false
    result.xHasHorizontalRuler = false
    result.xHasVerticalRuler = false
    result.xRulersVisible = false
    result.xScrollsDynamically = false
    result.xAutohidesScrollers = false
    result.xDocumentCursor = NSCursor(value: nil)
    result.setAutoresizesSubviews(true)

    let clipFrame = nsRect(0.0, 0.0, max(width.float32, 0.0), max(height.float32, 0.0))
    var clipView = NSClipView.new()
    clipView.setFrame(
      clipFrame.origin.x.float32, clipFrame.origin.y.float32,
      clipFrame.size.width.float32, clipFrame.size.height.float32,
    )
    clipView.setAutoresizingMask(NSViewWidthSizable or NSViewHeightSizable)
    clipView.setAutoresizesSubviews(true)
    result.xClipView = clipView
    result.addSubview(clipView)

  method init*(self: var NSScrollView): NSScrollView =
    result = self.initWithFrame(0.0, 0.0, 1.0, 1.0)

  method dealloc(self: NSScrollView) {.used.} =
    self.xClipView = NSClipView(value: nil)
    self.xHeaderClipView = NSClipView(value: nil)
    self.xCornerView = NSView(value: nil)
    self.xVerticalScroller = NSScroller(value: nil)
    self.xHorizontalScroller = NSScroller(value: nil)
    self.xHorizontalRuler = NSRulerView(value: nil)
    self.xVerticalRuler = NSRulerView(value: nil)
    self.xBackgroundColor = nsColor(0.0, 0.0, 0.0, 0.0)
    self.xDocumentCursor = NSCursor(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSScrollView, self, getSelector("dealloc"))

  method isOpaque*(self: NSScrollView): bool =
    self.xDrawsBackground

  method isFlipped*(self: NSScrollView): bool =
    true

  method contentSize*(self: NSScrollView): NSSize =
    if self.xClipView.isNil:
      return nsSize(0.0, 0.0)
    self.xClipView.frame().size

  method documentView*(self: NSScrollView): NSView =
    if self.xClipView.isNil:
      return NSView(value: nil)
    self.xClipView.documentView()

  method contentView*(self: NSScrollView): NSClipView =
    if self.xClipView.isNil:
      return NSClipView(value: nil)
    retain(self.xClipView)

  method documentVisibleRect*(self: NSScrollView): NSRect =
    if self.xClipView.isNil:
      return nsRect(0.0, 0.0, 0.0, 0.0)
    self.xClipView.documentVisibleRect()

  method drawsBackground*(self: NSScrollView): bool =
    self.xDrawsBackground

  method backgroundColor*(self: NSScrollView): NSColor =
    self.xBackgroundColor

  method borderType*(self: NSScrollView): NSBorderType =
    self.xBorderType

  method verticalScroller*(self: NSScrollView): NSScroller =
    if self.xVerticalScroller.isNil:
      return NSScroller(value: nil)
    retain(self.xVerticalScroller)

  method horizontalScroller*(self: NSScrollView): NSScroller =
    if self.xHorizontalScroller.isNil:
      return NSScroller(value: nil)
    retain(self.xHorizontalScroller)

  method verticalRulerView*(self: NSScrollView): NSRulerView =
    if self.xVerticalRuler.isNil:
      return NSRulerView(value: nil)
    retain(self.xVerticalRuler)

  method setVerticalRulerView*(self: NSScrollView, ruler: NSRulerView) =
    if not self.xVerticalRuler.isNil:
      self.xVerticalRuler.removeFromSuperview()
    self.xVerticalRuler =
      if ruler.isNil:
        NSRulerView(value: nil)
      else:
        retain(ruler)
    if not self.xVerticalRuler.isNil:
      self.xVerticalRuler.setScrollView(self)
      self.xVerticalRuler.setOrientation(NSVerticalRuler)
      self.addSubview(asRetainedType[NSView](self.xVerticalRuler))
    self.xHasVerticalRuler = not self.xVerticalRuler.isNil
    self.tile()

  method setHorizontalRulerView*(self: NSScrollView, ruler: NSRulerView) =
    if not self.xHorizontalRuler.isNil:
      self.xHorizontalRuler.removeFromSuperview()
    self.xHorizontalRuler =
      if ruler.isNil:
        NSRulerView(value: nil)
      else:
        retain(ruler)
    if not self.xHorizontalRuler.isNil:
      self.xHorizontalRuler.setScrollView(self)
      self.xHorizontalRuler.setOrientation(NSHorizontalRuler)
      self.addSubview(asRetainedType[NSView](self.xHorizontalRuler))
    self.xHasHorizontalRuler = not self.xHorizontalRuler.isNil
    self.tile()

  method horizontalRulerView*(self: NSScrollView): NSRulerView =
    if self.xHorizontalRuler.isNil:
      return NSRulerView(value: nil)
    retain(self.xHorizontalRuler)

  method hasVerticalScroller*(self: NSScrollView): bool =
    self.xHasVerticalScroller

  method hasHorizontalScroller*(self: NSScrollView): bool =
    self.xHasHorizontalScroller

  method hasVerticalRuler*(self: NSScrollView): bool =
    self.xHasVerticalRuler

  method hasHorizontalRuler*(self: NSScrollView): bool =
    self.xHasHorizontalRuler

  method rulersVisible*(self: NSScrollView): bool =
    self.xRulersVisible

  method verticalLineScroll*(self: NSScrollView): float32 =
    self.xVerticalLineScroll

  method horizontalLineScroll*(self: NSScrollView): float32 =
    self.xHorizontalLineScroll

  method verticalPageScroll*(self: NSScrollView): float32 =
    self.xVerticalPageScroll

  method horizontalPageScroll*(self: NSScrollView): float32 =
    self.xHorizontalPageScroll

  method lineScroll*(self: NSScrollView): float32 =
    self.xVerticalLineScroll

  method pageScroll*(self: NSScrollView): float32 =
    self.xVerticalPageScroll

  method scrollsDynamically*(self: NSScrollView): bool =
    self.xScrollsDynamically

  method autohidesScrollers*(self: NSScrollView): bool =
    self.xAutohidesScrollers

  method documentCursor*(self: NSScrollView): NSCursor =
    if self.xDocumentCursor.isNil:
      return NSCursor(value: nil)
    retain(self.xDocumentCursor)

  method setDocumentView*(self: NSScrollView, view: NSView) =
    if self.xClipView.isNil:
      return
    self.xClipView.setDocumentView(view)
    self.reflectScrolledClipView(self.xClipView)

  method setContentView*(self: NSScrollView, clipView: NSClipView) =
    if not self.xClipView.isNil:
      self.xClipView.removeFromSuperview()
    if clipView.isNil:
      let frame = self.clipViewFrame()
      self.xClipView = NSClipView.new()
      self.xClipView.setFrame(
        frame.origin.x.float32, frame.origin.y.float32, frame.size.width.float32,
        frame.size.height.float32,
      )
    else:
      self.xClipView = retain(clipView)
    self.addSubview(asRetainedType[NSView](self.xClipView))
    self.xClipView.setAutoresizingMask(NSViewWidthSizable or NSViewHeightSizable)
    self.xClipView.setAutoresizesSubviews(true)
    self.tile()

  method setDrawsBackground*(self: NSScrollView, value: bool) =
    self.xDrawsBackground = value
    if self.xClipView.isNil:
      return
    self.xClipView.setDrawsBackground(value)
    if not value:
      self.xClipView.setCopiesOnScroll(false)

  method setBackgroundColor*(self: NSScrollView, color: NSColor) =
    self.xBackgroundColor = color
    if not self.xClipView.isNil:
      self.xClipView.setBackgroundColor(color)

  method setBorderType*(self: NSScrollView, borderType: NSBorderType) =
    if self.xBorderType == borderType:
      return
    self.xBorderType = borderType
    self.tile()

  method setVerticalScroller*(self: NSScrollView, scroller: NSScroller) =
    if not self.xVerticalScroller.isNil:
      self.xVerticalScroller.removeFromSuperview()
    self.xVerticalScroller =
      if scroller.isNil:
        NSScroller(value: nil)
      else:
        retain(scroller)
    if not self.xVerticalScroller.isNil:
      self.xVerticalScroller.setTarget(ID(value: self.value))
      self.xVerticalScroller.setAction(getSelector("verticalScroll:"))
      if self.xHasVerticalScroller:
        self.addSubview(asRetainedType[NSView](self.xVerticalScroller))
    self.tile()

  method setHorizontalScroller*(self: NSScrollView, scroller: NSScroller) =
    if not self.xHorizontalScroller.isNil:
      self.xHorizontalScroller.removeFromSuperview()
    self.xHorizontalScroller =
      if scroller.isNil:
        NSScroller(value: nil)
      else:
        retain(scroller)
    if not self.xHorizontalScroller.isNil:
      self.xHorizontalScroller.setTarget(ID(value: self.value))
      self.xHorizontalScroller.setAction(getSelector("horizontalScroll:"))
      if self.xHasHorizontalScroller:
        self.addSubview(asRetainedType[NSView](self.xHorizontalScroller))
    self.tile()

  method setHasVerticalScroller*(self: NSScrollView, flag: bool) =
    if flag:
      if self.xHasVerticalScroller:
        return
      self.xHasVerticalScroller = true
      self.createVerticalScrollerIfNeeded()
      if not self.xVerticalScroller.isNil:
        self.addSubview(asRetainedType[NSView](self.xVerticalScroller))
      self.tile()
    else:
      if not self.xHasVerticalScroller:
        return
      self.xHasVerticalScroller = false
      if not self.xVerticalScroller.isNil:
        self.xVerticalScroller.removeFromSuperview()
      self.tile()

  method setHasHorizontalScroller*(self: NSScrollView, flag: bool) =
    if flag:
      if self.xHasHorizontalScroller:
        return
      self.xHasHorizontalScroller = true
      self.createHorizontalScrollerIfNeeded()
      if not self.xHorizontalScroller.isNil:
        self.addSubview(asRetainedType[NSView](self.xHorizontalScroller))
      self.tile()
    else:
      if not self.xHasHorizontalScroller:
        return
      self.xHasHorizontalScroller = false
      if not self.xHorizontalScroller.isNil:
        self.xHorizontalScroller.removeFromSuperview()
      self.tile()

  method setHasVerticalRuler*(self: NSScrollView, flag: bool) =
    if self.xHasVerticalRuler == flag:
      return
    self.xHasVerticalRuler = flag
    self.tile()
    if not self.xVerticalRuler.isNil:
      self.xVerticalRuler.setNeedsDisplay(flag)

  method setHasHorizontalRuler*(self: NSScrollView, flag: bool) =
    if self.xHasHorizontalRuler == flag:
      return
    self.xHasHorizontalRuler = flag
    self.tile()
    if not self.xHorizontalRuler.isNil:
      self.xHorizontalRuler.setNeedsDisplay(flag)

  method setRulersVisible*(self: NSScrollView, flag: bool) =
    if self.xRulersVisible == flag:
      return
    self.xRulersVisible = flag
    self.tile()

  method setVerticalLineScroll*(self: NSScrollView, value: float32) =
    if value > 0.0:
      self.xVerticalLineScroll = value

  method setHorizontalLineScroll*(self: NSScrollView, value: float32) =
    if value > 0.0:
      self.xHorizontalLineScroll = value

  method setVerticalPageScroll*(self: NSScrollView, value: float32) =
    if value > 0.0:
      self.xVerticalPageScroll = value

  method setHorizontalPageScroll*(self: NSScrollView, value: float32) =
    if value > 0.0:
      self.xHorizontalPageScroll = value

  method setLineScroll*(self: NSScrollView, value: float32) =
    self.setHorizontalLineScroll(value)
    self.setVerticalLineScroll(value)

  method setPageScroll*(self: NSScrollView, value: float32) =
    self.setHorizontalPageScroll(value)
    self.setVerticalPageScroll(value)

  method setScrollsDynamically*(self: NSScrollView, flag: bool) =
    self.xScrollsDynamically = flag

  method setDocumentCursor*(self: NSScrollView, cursor: NSCursor) =
    self.xDocumentCursor =
      if cursor.isNil:
        NSCursor(value: nil)
      else:
        retain(cursor)
    if not self.xClipView.isNil:
      self.xClipView.setDocumentCursor(self.xDocumentCursor)

  method setAutohidesScrollers*(self: NSScrollView, value: bool) =
    self.xAutohidesScrollers = value

  method createHeaderAndCornerViewsIfNeeded*(self: NSScrollView) =
    let headerView = self.headerViewInternal()
    if headerView.isNil:
      if not self.xHeaderClipView.isNil:
        self.xHeaderClipView.removeFromSuperview()
      self.xHeaderClipView = NSClipView(value: nil)
    elif self.xHeaderClipView.isNil:
      let frame = self.headerClipViewFrame()
      var headerClip = NSClipView.new()
      headerClip.setFrame(
        frame.origin.x.float32, frame.origin.y.float32, frame.size.width.float32,
        frame.size.height.float32,
      )
      headerClip.setDocumentView(headerView)
      self.addSubview(asRetainedType[NSView](headerClip))
      headerClip.setAutoresizingMask(NSViewWidthSizable or NSViewHeightSizable)
      headerClip.setAutoresizesSubviews(true)
      self.xHeaderClipView = headerClip

    let corner = self.cornerViewInternal()
    if corner.isNil:
      if not self.xCornerView.isNil:
        self.xCornerView.removeFromSuperview()
      self.xCornerView = NSView(value: nil)
    elif self.xCornerView.isNil:
      self.xCornerView = retain(corner)
      self.addSubview(self.xCornerView)

  method createRulerViewsIfNeeded*(self: NSScrollView) =
    if (not self.xHorizontalRuler.isNil) and
        (not self.xHorizontalRuler.superview().isNil):
      self.xHorizontalRuler.removeFromSuperview()
    if (not self.xVerticalRuler.isNil) and (not self.xVerticalRuler.superview().isNil):
      self.xVerticalRuler.removeFromSuperview()

    if not self.xRulersVisible:
      return
    if self.xHasHorizontalRuler:
      if self.xHorizontalRuler.isNil:
        self.xHorizontalRuler = newRulerView(self, NSHorizontalRuler)
      if not self.xHorizontalRuler.isNil:
        self.addSubview(asRetainedType[NSView](self.xHorizontalRuler))
    if self.xHasVerticalRuler:
      if self.xVerticalRuler.isNil:
        self.xVerticalRuler = newRulerView(self, NSVerticalRuler)
      if not self.xVerticalRuler.isNil:
        self.addSubview(asRetainedType[NSView](self.xVerticalRuler))

  method tile*(self: NSScrollView) =
    self.createHeaderAndCornerViewsIfNeeded()
    self.createRulerViewsIfNeeded()

    if not self.xHeaderClipView.isNil:
      self.xHeaderClipView.setFrame(self.headerClipViewFrame())
    if not self.xCornerView.isNil:
      self.xCornerView.setFrame(self.cornerViewFrame())
    if not self.xVerticalScroller.isNil:
      self.xVerticalScroller.setFrame(self.verticalScrollerFrame())
    if not self.xHorizontalScroller.isNil:
      self.xHorizontalScroller.setFrame(self.horizontalScrollerFrame())
    if not self.xClipView.isNil:
      self.xClipView.setFrame(self.clipViewFrame())
    if not self.xHorizontalRuler.isNil:
      self.xHorizontalRuler.setFrame(self.horizontalRulerFrame())
    if not self.xVerticalRuler.isNil:
      self.xVerticalRuler.setFrame(self.verticalRulerFrame())

    if not self.xClipView.isNil:
      var clipBounds = self.xClipView.bounds()
      if not self.xHasVerticalScroller:
        clipBounds.origin.y = 0.0
      if not self.xHasHorizontalScroller:
        clipBounds.origin.x = 0.0
      self.xClipView.setBoundsOrigin(clipBounds.origin)

    self.reflectScrolledClipView(self.xClipView)
    if (not self.xClipView.isNil) and (not self.xDocumentCursor.isNil):
      self.xClipView.setDocumentCursor(self.xDocumentCursor)

  method reflectScrolledClipView*(self: NSScrollView, clipView: NSClipView) =
    if self.xClipView.isNil or clipView.isNil or self.xClipView.value != clipView.value:
      return
    let docView = self.documentView()
    if docView.isNil:
      if not self.xVerticalScroller.isNil:
        self.xVerticalScroller.setEnabled(false)
        self.xVerticalScroller.setHidden(self.xAutohidesScrollers)
      if not self.xHorizontalScroller.isNil:
        self.xHorizontalScroller.setEnabled(false)
        self.xHorizontalScroller.setHidden(self.xAutohidesScrollers)
    else:
      let docRect = docView.frame()
      let clipRect = self.xClipView.bounds()
      let heightDiff = docRect.size.height - clipRect.size.height
      let widthDiff = docRect.size.width - clipRect.size.width

      if not self.xVerticalScroller.isNil:
        if heightDiff <= 0.0:
          self.xVerticalScroller.setEnabled(false)
          self.xVerticalScroller.setHidden(self.xAutohidesScrollers)
        else:
          var value = (clipRect.origin.y - docRect.origin.y) / heightDiff
          if not docView.isFlipped():
            value = 1.0 - value
          self.xVerticalScroller.setEnabled(true)
          self.xVerticalScroller.setHidden(false)
          self.xVerticalScroller.setFloatValue(
            value.float32,
            max(min(clipRect.size.height / max(docRect.size.height, 0.0001), 1.0), 0.0),
          )

      if not self.xHorizontalScroller.isNil:
        if widthDiff <= 0.0:
          self.xHorizontalScroller.setEnabled(false)
          self.xHorizontalScroller.setHidden(self.xAutohidesScrollers)
        else:
          let value = (clipRect.origin.x - docRect.origin.x) / widthDiff
          self.xHorizontalScroller.setEnabled(true)
          self.xHorizontalScroller.setHidden(false)
          self.xHorizontalScroller.setFloatValue(
            value.float32,
            max(min(clipRect.size.width / max(docRect.size.width, 0.0001), 1.0), 0.0),
          )

    if not self.xHorizontalRuler.isNil:
      self.xHorizontalRuler.invalidateHashMarks()
    if not self.xVerticalRuler.isNil:
      self.xVerticalRuler.invalidateHashMarks()

    if not self.xHeaderClipView.isNil and (not self.xClipView.isNil):
      var headerClipRect = self.xHeaderClipView.frame()
      headerClipRect.origin.x = self.xClipView.frame().origin.x
      headerClipRect.size.width = self.xClipView.frame().size.width
      self.xHeaderClipView.setFrame(headerClipRect)
      self.xHeaderClipView.setNeedsDisplay(true)

  method verticalScroll*(self: NSScrollView, scroller: NSScroller) =
    let docView = self.documentView()
    if docView.isNil or self.xClipView.isNil or scroller.isNil:
      return
    let docRect = docView.frame()
    var clipRect = self.xClipView.bounds()
    var lineScroll = self.xVerticalLineScroll
    var pageScroll = self.xVerticalPageScroll

    if not docView.isFlipped():
      lineScroll = -lineScroll
      pageScroll = -pageScroll

    case scroller.hitPart()
    of NSScrollerIncrementLine:
      clipRect.origin.y += lineScroll
    of NSScrollerDecrementLine:
      clipRect.origin.y -= lineScroll
    of NSScrollerIncrementPage:
      clipRect.origin.y += pageScroll
    of NSScrollerDecrementPage:
      clipRect.origin.y -= pageScroll
    else:
      var value = scroller.floatValue()
      if not docView.isFlipped():
        value = 1.0 - value
      value *= max(docRect.size.height - clipRect.size.height, 0.0)
      clipRect.origin.y = docRect.origin.y + floor(value)

    self.xClipView.scrollToPoint(clipRect.origin)
    let parent = self.superview()
    if not parent.isNil:
      parent.setNeedsDisplay(true)

  method horizontalScroll*(self: NSScrollView, scroller: NSScroller) =
    let docView = self.documentView()
    if docView.isNil or self.xClipView.isNil or scroller.isNil:
      return
    let docRect = docView.frame()
    var clipRect = self.xClipView.bounds()
    var headerClipRect =
      if self.xHeaderClipView.isNil:
        nsRect(0.0, 0.0, 0.0, 0.0)
      else:
        self.xHeaderClipView.bounds()

    case scroller.hitPart()
    of NSScrollerIncrementLine:
      clipRect.origin.x += self.xHorizontalLineScroll
    of NSScrollerDecrementLine:
      clipRect.origin.x -= self.xHorizontalLineScroll
    of NSScrollerIncrementPage:
      clipRect.origin.x += self.xHorizontalPageScroll
    of NSScrollerDecrementPage:
      clipRect.origin.x -= self.xHorizontalPageScroll
    else:
      let value =
        scroller.floatValue() * max(docRect.size.width - clipRect.size.width, 0.0)
      clipRect.origin.x = docRect.origin.x + floor(value)

    headerClipRect.origin.x = clipRect.origin.x
    self.xClipView.scrollToPoint(clipRect.origin)
    if not self.xHeaderClipView.isNil:
      self.xHeaderClipView.scrollToPoint(headerClipRect.origin)
    let parent = self.superview()
    if not parent.isNil:
      parent.setNeedsDisplay(true)

  method resizeSubviewsWithOldSize*(self: NSScrollView, oldSize: NSSize) =
    discard oldSize
    self.tile()
    if self.hasVerticalScroller() and (not self.xVerticalScroller.isNil):
      self.verticalScroll(self.xVerticalScroller)
    if self.hasHorizontalScroller() and (not self.xHorizontalScroller.isNil):
      self.horizontalScroll(self.xHorizontalScroller)

proc frameSizeForContentSize*(
    t: typedesc[NSScrollView],
    contentSize: NSSize,
    hasHorizontalScroller: bool,
    hasVerticalScroller: bool,
    borderType: NSBorderType,
): NSSize =
  discard
  result = contentSize
  if hasHorizontalScroller:
    result.height += NSScroller.scrollerWidth()
  if hasVerticalScroller:
    result.width += NSScroller.scrollerWidth()
  case borderType
  of NSNoBorder:
    discard
  of NSLineBorder:
    result.height += 1.0
    result.width += 1.0
  of NSBezelBorder, NSGrooveBorder:
    result.height += 2.0
    result.width += 2.0

proc contentSizeForFrameSize*(
    t: typedesc[NSScrollView],
    frameSize: NSSize,
    hasHorizontalScroller: bool,
    hasVerticalScroller: bool,
    borderType: NSBorderType,
): NSSize =
  discard
  result = frameSize
  if hasHorizontalScroller:
    result.height -= NSScroller.scrollerWidth()
  if hasVerticalScroller:
    result.width -= NSScroller.scrollerWidth()
  case borderType
  of NSNoBorder:
    discard
  of NSLineBorder:
    result.height -= 1.0
    result.width -= 1.0
  of NSBezelBorder, NSGrooveBorder:
    result.height -= 2.0
    result.width -= 2.0

proc setRulerViewClass*(t: typedesc[NSScrollView], cls: ObjcClass) =
  discard
  rulerViewImplClass = cls

proc rulerViewClass*(t: typedesc[NSScrollView]): ObjcClass =
  discard
  currentRulerClass()

proc new*(t: typedesc[NSScrollView]): NSScrollView =
  var allocated = NSScrollView.alloc()
  result = initOwned(move(allocated))
