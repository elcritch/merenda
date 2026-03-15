import std/[math, times]

import ./runtime
import ./views
import ./controls
import ./textfields
import ./windows
import ./scrollviews
import ./graphics
import ./colors
import ./fonts
import ./attributedstrings
import ./events

const ComboBoxTrackingMaxWaitSeconds = 86_400.0

type
  ComboBoxKeyboardUIState = enum
    ComboKeyboardInactive
    ComboKeyboardActive
    ComboKeyboardOk
    ComboKeyboardCancel

  ComboBoxTrackingState = enum
    ComboTrackFirstMouseDown
    ComboTrackMouseDown
    ComboTrackMouseUp
    ComboTrackExit

proc referenceTimestampNow(): float =
  epochTime() - 978_307_200.0

proc insetRect(rect: NSRect, dx: float32, dy: float32): NSRect {.inline.} =
  nsRect(
    rect.origin.x + dx,
    rect.origin.y + dy,
    max(rect.size.width - 2.0 * dx, 0.0),
    max(rect.size.height - 2.0 * dy, 0.0),
  )

proc pointsEqual(a: NSPoint, b: NSPoint): bool {.inline.} =
  a.x == b.x and a.y == b.y

proc packedForegroundStyle(foreground: NSColor): int {.inline.} =
  (((foreground.r * 255.0'f32).int and 0xFF) shl 24) or
    (((foreground.g * 255.0'f32).int and 0xFF) shl 16) or
    (((foreground.b * 255.0'f32).int and 0xFF) shl 8) or
    ((foreground.a * 255.0'f32).int and 0xFF)

proc foregroundColorAttributeKey(): NSString {.inline.} =
  if NSForegroundColorAttributeName.isNil:
    @ns"NSForegroundColorAttributeName"
  else:
    NSForegroundColorAttributeName

proc comboBoxItemAttributes(selected: bool): NSDictionary[NSObject, NSObject] =
  result = nsDictionary[NSObject, NSObject]()
  if selected:
    result[NSObject(foregroundColorAttributeKey())] =
      boxNSObject(packedForegroundStyle(NSColor.selectedTextColor()))

proc refreshPopupItemAttributes(self: auto) =
  if self.isNil:
    return
  let itemAttributes = comboBoxItemAttributes(false)
  let selectedItemAttributes = comboBoxItemAttributes(true)
  self.xItemAttributesId.value =
    replacedOwnedId(self.xItemAttributesId.value, itemAttributes.value)
  self.xSelectedItemAttributesId.value =
    replacedOwnedId(self.xSelectedItemAttributesId.value, selectedItemAttributes.value)

proc addAuxiliaryWindow(owner: NSWindow, auxiliary: NSWindow) =
  if owner.isNil or auxiliary.isNil:
    return
  var current = owner.nextResponder()
  while not current.isNil:
    if current.respondsToSelector("addWindow:"):
      cast[proc(self: IDPtr, op: SEL, windowId: IDPtr) {.cdecl, varargs.}](objc_msgSend)(
        current.value, getSelector("addWindow:"), auxiliary.value
      )
      return
    current = current.nextResponder()

proc lookupWindowByNumber(owner: NSWindow, number: NSInteger): NSWindow =
  if owner.isNil or number <= 0:
    return NSWindow(value: nil)
  var current = owner.nextResponder()
  while not current.isNil:
    if current.respondsToSelector("windowWithWindowNumber:"):
      let raw = cast[proc(self: IDPtr, op: SEL, windowNumber: NSInteger): IDPtr {.
        cdecl, varargs
      .}](objc_msgSend)(current.value, getSelector("windowWithWindowNumber:"), number)
      return NSWindow(value: raw)
    current = current.nextResponder()
  NSWindow(value: nil)

proc comboBoxArrowZoneRect*(controlBox: NSRect): NSRect =
  # Cocotron uses a square arrow button (width == control height).
  let arrowWidth =
    min(max(controlBox.size.height, 0.0), max(controlBox.size.width, 0.0))
  let zoneWidth = min(arrowWidth, max(controlBox.size.width, 0.0))
  nsRect(
    controlBox.origin.x + controlBox.size.width - zoneWidth,
    controlBox.origin.y,
    zoneWidth,
    controlBox.size.height,
  )

proc comboBoxPopupItemHeight*[T](comboBox: T): float32 =
  max(comboBox.itemHeight() + 6.0, 18.0)

proc comboBoxVisiblePopupItems*[T](comboBox: T): int =
  let count = comboBox.numberOfItems()
  if count <= 0:
    return 0
  let requested = comboBox.numberOfVisibleItems()
  if requested <= 0:
    return count
  min(count, requested)

proc comboBoxPopupFirstItemIndex*[T](comboBox: T): int =
  let total = comboBox.numberOfItems()
  let visible = comboBoxVisiblePopupItems(comboBox)
  if total <= 0 or visible <= 0:
    return 0
  if total <= visible:
    return 0
  let selected = comboBox.indexOfSelectedItem()
  if selected < 0:
    return 0
  clamp(selected - visible + 1, 0, total - visible)

proc comboBoxPopupFrame*[T](comboBox: T, controlBox: NSRect): NSRect =
  let itemCount = comboBoxVisiblePopupItems(comboBox)
  if itemCount <= 0:
    return nsRect(controlBox.origin.x, controlBox.origin.y, 0.0, 0.0)
  let popupHeight = comboBoxPopupItemHeight(comboBox) * itemCount.float32 + 2.0
  nsRect(
    controlBox.origin.x,
    controlBox.origin.y + controlBox.size.height,
    max(controlBox.size.width, 0.0),
    popupHeight,
  )

proc comboBoxPopupItemIndexAtPoint*(
  comboBox: auto, controlBox: NSRect, x: float32, y: float32
): int

proc comboBoxDisplayString(value: NSObject): NSString =
  if value.isNil:
    return @ns""
  if value.isKindOfClass(NSString):
    return value.NSString
  if value.isKindOfClass(NSAttributedString):
    return value.NSAttributedString.string()
  ns($value)

proc comboBoxPopupItemRect*(
    comboBox: auto, controlBox: NSRect, itemIndex: int
): NSRect =
  let firstIndex = comboBoxPopupFirstItemIndex(comboBox)
  let visibleIndex = itemIndex - firstIndex
  if visibleIndex < 0 or visibleIndex >= comboBoxVisiblePopupItems(comboBox):
    return nsRect(controlBox.origin.x, controlBox.origin.y, 0.0, 0.0)
  let popupBox = comboBoxPopupFrame(comboBox, controlBox)
  let itemHeight = comboBoxPopupItemHeight(comboBox)
  let yTop =
    popupBox.origin.y + popupBox.size.height - 1.0 - visibleIndex.float32 * itemHeight
  nsRect(
    popupBox.origin.x + 1.0,
    yTop - itemHeight,
    max(popupBox.size.width - 2.0, 0.0),
    max(itemHeight, 0.0),
  )

objcImpl:
  type NSComboBoxView* = object of NSView
    xObjects: seq[string]
    xSelectedIndex {.get: selectedIndex.}: int
    xCellSize {.get: cellSize.}: NSSize
    xFontSize: float32
    xItemAttributesId: ID
    xSelectedItemAttributesId: ID
    xKeyboardUIState: ComboBoxKeyboardUIState

  method init*(self: var NSComboBoxView): NSComboBoxView =
    result = NSComboBoxView(value: nil)
    result = asTypeRaw[NSComboBoxView](
      callSuperIdFrom(NSComboBoxView, self, getSelector("init"))
    )
    if result.isNil:
      return
    initIvarFields(result)
    result.xObjects = @[]
    result.xSelectedIndex = -1
    result.xCellSize = nsSize(120.0, 22.0)
    result.xFontSize = 12.0
    result.xKeyboardUIState = ComboKeyboardInactive
    refreshPopupItemAttributes(result)

  method initWithFrame*(self: var NSComboBoxView, rect: NSRect): NSComboBoxView =
    result = NSComboBoxView(value: nil)
    result = self.init()
    if result.isNil:
      return
    result.setFrame(rect)
    result.xCellSize = nsSize(max(rect.size.width, 1.0), max(rect.size.height, 1.0))

  method isFlipped*(self: NSComboBoxView): bool =
    false

  method setObjectArray*(self: NSComboBoxView, objects: NSArray[NSString]) =
    self.xObjects = @[]
    for item in objects:
      if item.isNil:
        self.xObjects.add("")
      else:
        self.xObjects.add($item)

  method setCellSize*(self: NSComboBoxView, value: NSSize) =
    self.xCellSize = nsSize(max(value.width, 1.0), max(value.height, 1.0))

  method setSelectedIndex*(self: NSComboBoxView, index: int) =
    if self.xObjects.len == 0:
      self.xSelectedIndex = -1
      return
    if index < 0:
      self.xSelectedIndex = -1
      return
    self.xSelectedIndex = min(index, self.xObjects.len - 1)

  method font*(self: NSComboBoxView): NSFont =
    NSFont.messageFontOfSize(max(self.xFontSize, 1.0))

  method setFont*(self: NSComboBoxView, font: NSFont) =
    if font.isNil:
      self.xFontSize = 12.0
    else:
      self.xFontSize = max(font.pointSize(), 1.0)
    refreshPopupItemAttributes(self)

  method itemAttributes*(self: NSComboBoxView): NSDictionary[NSObject, NSObject] =
    if self.xItemAttributesId.value.isNil:
      refreshPopupItemAttributes(self)
    ownFromId[NSDictionary[NSObject, NSObject]](self.xItemAttributesId)

  method selectedItemAttributes*(
      self: NSComboBoxView
  ): NSDictionary[NSObject, NSObject] =
    if self.xSelectedItemAttributesId.value.isNil:
      refreshPopupItemAttributes(self)
    ownFromId[NSDictionary[NSObject, NSObject]](self.xSelectedItemAttributesId)

  method sizeForContents*(self: NSComboBoxView): NSSize =
    let count = self.xObjects.len
    var result = nsSize(max(self.bounds().size.width, 1.0), 0.0)
    result.height += count.float32 * self.xCellSize.height
    result

  method itemIndexForPoint*(self: NSComboBoxView, point: NSPoint): int =
    if self.xObjects.len == 0 or self.xCellSize.height <= 0.0:
      return -1
    let boundsHeight = max(self.bounds().size.height, 0.0)
    let distanceFromTop = boundsHeight - point.y
    let index = floor(distanceFromTop / self.xCellSize.height).int
    if index < 0 or index >= self.xObjects.len:
      return -1
    index

  method rectForItemAtIndex*(self: NSComboBoxView, index: int): NSRect =
    var result = nsRect(0.0, 0.0, self.xCellSize.width, self.xCellSize.height)
    let boundsHeight = max(self.bounds().size.height, 0.0)
    result.origin.y = boundsHeight - (index.float32 + 1.0) * self.xCellSize.height
    result

  method drawItemAtIndex*(self: NSComboBoxView, index: int) =
    if index < 0 or index >= self.xObjects.len:
      return
    let item = self.xObjects[index]
    let attributes =
      if index == self.xSelectedIndex:
        self.selectedItemAttributes()
      else:
        self.itemAttributes()
    var itemRect = self.rectForItemAtIndex(index)
    if index == self.xSelectedIndex:
      NSColor.selectedTextBackgroundColor().setFill()
      NSRectFill(itemRect)
    else:
      NSColor.textBackgroundColor().setFill()
      NSRectFill(itemRect)

    itemRect = insetRect(itemRect, 1.0, 1.0)
    let text = ns(item)
    var attributedAlloc = NSAttributedString.alloc()
    let attributed = attributedAlloc.initWithString(text, attributes = attributes)
    attributedAlloc.value = nil
    if attributed.isNil:
      return
    let stringSize = attributed.size()
    let textHeight = max(stringSize.height, 1.0)
    itemRect.origin.y += floor((self.xCellSize.height - textHeight) / 2.0)
    itemRect.size.height = textHeight
    attributed.drawInRect(itemRect)

  method drawRect*(self: NSComboBoxView, rect: NSRect) =
    discard rect
    NSColor.textBackgroundColor().setFill()
    NSRectFill(self.bounds())
    for i in 0 ..< self.xObjects.len:
      self.drawItemAtIndex(i)

  method rightMouseDown*(self: NSComboBoxView, event: NSEvent) =
    discard

  method pointInSelfForEvent*(self: NSComboBoxView, event: NSEvent): NSPoint =
    if event.isNil:
      return nsPoint(0.0, 0.0)
    var point = event.locationInWindow()
    let targetWindow = self.window()
    if targetWindow.isNil:
      return point
    let sourceNumber = event.windowNumber()
    if sourceNumber != 0 and sourceNumber != targetWindow.windowNumber():
      let sourceWindow = lookupWindowByNumber(targetWindow, sourceNumber)
      if not sourceWindow.isNil:
        let screenPoint = sourceWindow.convertBaseToScreen(point)
        point = targetWindow.convertScreenToBase(screenPoint)
    self.convertPoint(point, NSView(value: nil))

  method runTrackingWithEvent*(self: NSComboBoxView, event: NSEvent): int =
    if self.isNil:
      return -1
    var state = ComboTrackFirstMouseDown
    var point = self.pointInSelfForEvent(event)
    let firstLocation = point
    let initialSelectedIndex = self.xSelectedIndex
    var cancelled = false
    var accepted = false

    while (not cancelled) and state != ComboTrackExit:
      let index = self.itemIndexForPoint(point)
      if index >= 0 and self.xKeyboardUIState == ComboKeyboardInactive:
        if self.xSelectedIndex != index:
          self.xSelectedIndex = index
          self.setNeedsDisplay(true)

      self.window().flushWindow()

      let nextEvent = self.window().nextEventMatchingMask(
          NSLeftMouseDownMask + NSLeftMouseUpMask + NSLeftMouseDraggedMask +
            NSMouseMovedMask + NSKeyDownMask,
          referenceTimestampNow() + ComboBoxTrackingMaxWaitSeconds,
          @ns"NSDefaultRunLoopMode",
          true,
        )
      if nextEvent.isNil:
        break

      if nextEvent.`type`() == NSKeyDown:
        self.interpretKeyEvents(@[nextEvent])
        case self.xKeyboardUIState
        of ComboKeyboardInactive:
          self.xKeyboardUIState = ComboKeyboardActive
          continue
        of ComboKeyboardActive:
          discard
        of ComboKeyboardCancel:
          self.xSelectedIndex = initialSelectedIndex
          state = ComboTrackExit
        of ComboKeyboardOk:
          accepted = self.xSelectedIndex >= 0
          state = ComboTrackExit
      else:
        self.xKeyboardUIState = ComboKeyboardInactive

      if nextEvent.`type`() == NSAppKitDefined:
        try:
          if nextEvent.subtype() == NSApplicationDeactivated.cshort:
            cancelled = true
        except ValueError:
          discard

      point = self.pointInSelfForEvent(nextEvent)

      case state
      of ComboTrackFirstMouseDown:
        if pointsEqual(firstLocation, point):
          if nextEvent.`type`() == NSLeftMouseUp:
            state = ComboTrackMouseUp
        else:
          state = ComboTrackMouseDown
      of ComboTrackMouseUp:
        if nextEvent.`type`() == NSLeftMouseDown:
          if index >= 0:
            state = ComboTrackMouseDown
          else:
            self.xSelectedIndex = initialSelectedIndex
            state = ComboTrackExit
      else:
        if nextEvent.`type`() == NSLeftMouseUp:
          accepted = index >= 0
          if not accepted:
            self.xSelectedIndex = initialSelectedIndex
          state = ComboTrackExit

    self.xKeyboardUIState = ComboKeyboardInactive
    if accepted: self.xSelectedIndex else: -1

  method keyDown*(self: NSComboBoxView, event: NSEvent) =
    self.interpretKeyEvents(@[event])

  method moveUp*(self: NSComboBoxView, sender: NSObject) =
    if self.xObjects.len == 0:
      self.xSelectedIndex = -1
      return
    if self.xSelectedIndex <= 0:
      self.xSelectedIndex = 0
    else:
      dec self.xSelectedIndex
    self.setNeedsDisplay(true)

  method moveDown*(self: NSComboBoxView, sender: NSObject) =
    if self.xObjects.len == 0:
      self.xSelectedIndex = -1
      return
    if self.xSelectedIndex < 0:
      self.xSelectedIndex = 0
    elif self.xSelectedIndex < self.xObjects.len - 1:
      inc self.xSelectedIndex
    self.setNeedsDisplay(true)

  method cancel*(self: NSComboBoxView, sender: NSObject) =
    self.xKeyboardUIState = ComboKeyboardCancel

  method insertNewline*(self: NSComboBoxView, sender: NSObject) =
    self.xKeyboardUIState = ComboKeyboardOk

  method dealloc(self: NSComboBoxView) {.used.} =
    self.xObjects = @[]
    destroyIvarFields(self)
    discard callSuperIdFrom(NSComboBoxView, self, getSelector("dealloc"))

objcImpl:
  type NSComboBoxWindow* = object of NSPanel
    xComboBox: ID
    xScrollView: NSScrollView
    xView: NSComboBoxView

  method initWithFrame*(self: var NSComboBoxWindow, frame: NSRect): NSComboBoxWindow =
    var base = self.initWithContentRect(
      frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
      NSBorderlessWindowMask, NSBackingStoreBuffered, false,
    )
    result = asTypeRaw[NSComboBoxWindow](base.value)
    base.value = nil
    if result.isNil:
      return
    initIvarFields(result)
    result.setReleasedWhenClosed(true)

    var contentAlloc = NSView.alloc()
    var contentView = contentAlloc.initWithFrame(
      nsRect(0.0, 0.0, max(frame.size.width, 1.0), max(frame.size.height, 1.0))
    )
    contentAlloc.value = nil
    result.setContentView(contentView)

    var scrollAlloc = NSScrollView.alloc()
    result.xScrollView = scrollAlloc.initWithFrame(
      0.0, 0.0, max(frame.size.width, 1.0), max(frame.size.height, 1.0)
    )
    scrollAlloc.value = nil
    result.xScrollView.setHasVerticalScroller(false)
    result.xScrollView.setHasHorizontalScroller(false)
    result.xScrollView.setBorderType(NSLineBorder)
    contentView.addSubview(result.xScrollView)

    let clipSize = result.xScrollView.contentSize()
    var viewAlloc = NSComboBoxView.alloc()
    result.xView = viewAlloc.initWithFrame(
      nsRect(0.0, 0.0, max(clipSize.width, 1.0), max(clipSize.height, 1.0))
    )
    viewAlloc.value = nil
    result.xScrollView.setDocumentView(result.xView)
    contentView.value = nil

  method init*(self: var NSComboBoxWindow): NSComboBoxWindow =
    self.initWithFrame(nsRect(0.0, 0.0, 1.0, 1.0))

  method setObjectArray*(self: NSComboBoxWindow, objects: NSArray[NSString]) =
    if self.xView.isNil:
      return
    self.xView.setObjectArray(objects)

  method setFont*(self: NSComboBoxWindow, font: NSFont) =
    if self.xView.isNil:
      return
    self.xView.setFont(font)

  method setSelectedIndex*(self: NSComboBoxWindow, index: int) =
    if self.xView.isNil:
      return
    self.xView.setSelectedIndex(index)

  method setCellHeight*(self: NSComboBoxWindow, height: float32) =
    if self.xView.isNil:
      return
    let current = self.xView.cellSize()
    self.xView.setCellSize(nsSize(current.width, max(height, 1.0)))

  method sizeToContents*(self: NSComboBoxWindow) =
    if self.isNil or self.xView.isNil or self.xScrollView.isNil:
      return

    let size = self.xView.sizeForContents()
    let scrollViewSize = NSScrollView.frameSizeForContentSize(
      size,
      self.xScrollView.hasHorizontalScroller(),
      self.xScrollView.hasVerticalScroller(),
      NSLineBorder,
    )
    var frame = self.frame()
    frame.size = scrollViewSize
    self.setFrame(frame)

    self.xScrollView.setFrameSize(scrollViewSize)
    self.xScrollView.setFrameOrigin(nsPoint(0.0, 0.0))
    self.xView.setFrameSize(size)
    self.xView.setFrameOrigin(nsPoint(0.0, 0.0))

  method runTrackingWithEvent*(self: NSComboBoxWindow, event: NSEvent): int =
    if self.isNil or self.xView.isNil or self.xScrollView.isNil:
      return -1
    self.sizeToContents()
    self.xView.runTrackingWithEvent(event)

  method dealloc(self: NSComboBoxWindow) {.used.} =
    self.xComboBox.value = nil
    self.xView = NSComboBoxView(value: nil)
    self.xScrollView = NSScrollView(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSComboBoxWindow, self, getSelector("dealloc"))

objcImpl:
  type NSComboBox* = object of NSTextField
    xObjectValues: seq[NSString]
    xSelectedIndex: int
    xDataSource: ID
    xUsesDataSource {.set: setUsesDataSource, get: usesDataSource.}: bool
    xButtonBordered {.set: setButtonBordered, get: isButtonBordered.}: bool
    xItemHeight {.set: setItemHeight, get: itemHeight.}: float32
    xHasVerticalScroller {.set: setHasVerticalScroller, get: hasVerticalScroller.}: bool
    xIntercellSpacing {.set: setIntercellSpacing, get: intercellSpacing.}: NSSize
    xCompletes {.set: setCompletes, get: completes.}: bool
    xNumberOfVisibleItems {.set: setNumberOfVisibleItems, get: numberOfVisibleItems.}:
      int
    xPopupOpen {.set: setPopupOpen, get: popupOpen.}: bool
    xPopupHoveredIndex {.set: setPopupHoveredIndex, get: popupHoveredIndex.}: int
    xPopupWindow {.set: setPopupWindow, get: popupWindow.}: NSComboBoxWindow
    xPopupTracking {.set: setPopupTracking, get: popupTracking.}: bool
    xButtonPressed {.set: setButtonPressed, get: buttonPressed.}: bool

  method init*(self: var NSComboBox): NSComboBox =
    result =
      asTypeRaw[NSComboBox](callSuperIdFrom(NSComboBox, self, getSelector("init")))
    if result.isNil:
      return
    initIvarFields(result)
    result.xObjectValues = @[]
    result.xSelectedIndex = -1
    result.xDataSource.value = nil
    result.xUsesDataSource = false
    result.xButtonBordered = true
    result.xItemHeight = 16.0
    result.xHasVerticalScroller = false
    result.xIntercellSpacing = nsSize(3.0, 2.0)
    result.xCompletes = false
    result.xNumberOfVisibleItems = 5
    result.xPopupOpen = false
    result.xPopupHoveredIndex = -1
    result.xPopupWindow = NSComboBoxWindow(value: nil)
    result.xPopupTracking = false
    result.xButtonPressed = false
    result.setEditable(true)

  method initWithFrame*(
      self: var NSComboBox,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSComboBox =
    result = self.init()
    if result.isNil:
      return
    result.to(NSView).setFrame(
      nsRect(
        x.float32, y.float32, max(width.float32, 0.0'f32), max(height.float32, 0.0'f32)
      )
    )

  method comboBox*(self: NSComboBoxWindow): NSComboBox =
    if self.isNil or self.xComboBox.isNil:
      return NSComboBox(value: nil)
    self.xComboBox.value.NSObject.NSComboBox

  method setComboBox*(self: NSComboBoxWindow, comboBox: NSComboBox) =
    if self.isNil:
      return
    self.xComboBox.value = comboBox.value

  method popupWindowFrame*(self: NSComboBox): NSRect =
    let ownerWindow = self.window()
    if ownerWindow.isNil:
      return nsRect(0.0, 0.0, 1.0, 1.0)
    let bounds = self.bounds()
    var origin = nsPoint(bounds.origin.x, bounds.origin.y + bounds.size.height)
    origin = self.NSView.convertPointToView(origin, NSView(value: nil))
    origin = ownerWindow.convertBaseToScreen(origin)
    nsRect(
      origin.x,
      origin.y,
      max(bounds.size.width + 1.0, 1.0),
      max(bounds.size.height, 1.0),
    )

  method ensurePopupWindow*(self: NSComboBox): NSComboBoxWindow =
    if not self.xPopupWindow.isNil and not self.xPopupWindow.windowClosed():
      self.xPopupWindow.setFrame(self.popupWindowFrame())
      return self.xPopupWindow

    var popupAlloc = NSComboBoxWindow.alloc()
    let popup = popupAlloc.initWithFrame(self.popupWindowFrame())
    popupAlloc.value = nil
    if popup.isNil:
      return NSComboBoxWindow(value: nil)
    let owner = self.window()
    if not owner.isNil:
      addAuxiliaryWindow(owner, popup.NSWindow)
    self.xPopupWindow = popup
    popup

  method configurePopupWindow*(self: NSComboBox, popup: NSComboBoxWindow) =
    if self.isNil or popup.isNil:
      return
    popup.setComboBox(self)
    popup.setFrame(self.popupWindowFrame())
    popup.setObjectArray(self.objectValues())
    popup.setSelectedIndex(self.indexOfSelectedItem())
    popup.setCellHeight(comboBoxPopupItemHeight(self))
    let comboFont = self.font()
    if not comboFont.isNil:
      popup.setFont(comboFont)
    popup.sizeToContents()
    self.xPopupOpen = true
    self.xPopupHoveredIndex = self.indexOfSelectedItem()

  method reactivateOwnerWindow*(self: NSComboBox) =
    let ownerWindow = self.window()
    if ownerWindow.isNil:
      return
    ownerWindow.makeKeyAndOrderFront(self.NSObject)
    discard ownerWindow.makeFirstResponder(self.NSResponder)

  method closePopupWindow*(self: NSComboBox) =
    if self.xPopupWindow.isNil:
      return
    if not self.xPopupWindow.windowClosed():
      self.xPopupWindow.close()
    self.xPopupWindow = NSComboBoxWindow(value: nil)
    self.reactivateOwnerWindow()

  method trackPopupWithEvent*(self: NSComboBox, event: NSEvent): int =
    result = -1
    if self.numberOfItems() <= 0:
      return
    let popup = self.ensurePopupWindow()
    if popup.isNil:
      return
    self.configurePopupWindow(popup)
    self.xPopupTracking = true
    popup.makeKeyAndOrderFront(self.NSObject)
    result = popup.runTrackingWithEvent(event)
    self.xPopupTracking = false
    self.closePopupWindow()
    self.xPopupOpen = false
    self.xPopupHoveredIndex = -1

  method drawRect*(self: NSComboBox, rect: NSRect) =
    discard rect
    if self.isNil:
      return

    let bounds = self.bounds()
    var valueRect = nsRect(
      bounds.origin.x + 3.0,
      bounds.origin.y + 3.0,
      max(bounds.size.width - 6.0, 0.0),
      max(bounds.size.height - 6.0, 0.0),
    )
    if self.isBezeled():
      NSDrawWhiteBezel(bounds, bounds)
      valueRect = nsRect(
        valueRect.origin.x - 1.0,
        valueRect.origin.y - 1.0,
        valueRect.size.width + 2.0,
        valueRect.size.height + 2.0,
      )
    elif self.isBordered():
      NSFrameRect(bounds)
      valueRect = nsRect(
        valueRect.origin.x - 1.0,
        valueRect.origin.y - 1.0,
        valueRect.size.width + 2.0,
        valueRect.size.height + 2.0,
      )
    if self.drawsBackground():
      self.backgroundColor().setFill()
      NSRectFill(valueRect)

    let arrowZone = comboBoxArrowZoneRect(bounds)
    let leftInset = 10.0'f32
    # Reserve only the trailing arrow button width plus a small gap.
    let rightInset =
      if arrowZone.size.width > 0.0:
        arrowZone.size.width + 4.0
      else:
        4.0
    let textRect = nsRect(
      bounds.origin.x + leftInset,
      bounds.origin.y + 4.0,
      max(bounds.size.width - leftInset - rightInset, 0.0),
      max(bounds.size.height - 8.0, 0.0),
    )
    let fontKey =
      if NSFontAttributeName.isNil:
        @ns"NSFontAttributeName"
      else:
        NSFontAttributeName
    var drawAttributes = nsDictionary[NSObject, NSObject]()
    var comboFont = self.font()
    if not comboFont.isNil:
      drawAttributes[NSObject(fontKey)] = NSObject(comboFont)
    var currentValueAlloc = NSAttributedString.alloc()
    var currentValue =
      currentValueAlloc.initWithString(self.stringValue(), attributes = drawAttributes)
    currentValueAlloc.value = nil
    if currentValue.isNil:
      var fallbackAlloc = NSAttributedString.alloc()
      currentValue = fallbackAlloc.initWithString(self.stringValue())
      fallbackAlloc.value = nil
    if not currentValue.isNil:
      currentValue.drawInRect(textRect)

    if arrowZone.size.width > 0.0 and arrowZone.size.height > 0.0:
      let arrowFill = if self.buttonPressed() or self.popupOpen(): 0.88 else: 0.95
      NSColor.colorWithCalibratedWhite(arrowFill, 1.0).setFill()
      NSRectFill(arrowZone)
      NSColor.colorWithCalibratedWhite(0.66, 1.0).setFill()
      NSRectFill(
        nsRect(
          arrowZone.origin.x,
          arrowZone.origin.y + 1.0,
          1.0,
          max(arrowZone.size.height - 2.0, 0.0),
        )
      )

      let triangleWidth = max(min(arrowZone.size.width * 0.28, 6.0), 4.0)
      let centerX = arrowZone.origin.x + arrowZone.size.width * 0.5
      let centerY = arrowZone.origin.y + arrowZone.size.height * 0.5
      NSColor.colorWithCalibratedWhite(0.26, 1.0).setFill()
      NSRectFill(
        nsRect(centerX - triangleWidth * 0.2, centerY + 1.0, triangleWidth * 0.4, 1.0)
      )
      NSRectFill(
        nsRect(centerX - triangleWidth * 0.35, centerY, triangleWidth * 0.7, 1.0)
      )
      NSRectFill(
        nsRect(centerX - triangleWidth * 0.5, centerY - 1.0, triangleWidth, 1.0)
      )

  method dataSource*(self: NSComboBox): ID =
    retainId(self.xDataSource)

  method setStringValue*(self: NSComboBox, value: NSString) =
    if value.isNil:
      self.xStringValue = @ns""
    else:
      self.xStringValue = value
    self.setNeedsDisplay(true)
    self.xSelectedIndex = -1
    let currentValue = self.stringValue()
    if not currentValue.isNil:
      let needle = $currentValue
      for idx, candidate in self.xObjectValues:
        if $candidate == needle:
          self.xSelectedIndex = idx
          break
    if self.xPopupOpen:
      self.xPopupHoveredIndex = self.xSelectedIndex

  method setObjectValue*(self: NSComboBox, value: NSObject) =
    self.setStringValue(comboBoxDisplayString(value))

  method setDataSource*(self: NSComboBox, value: ID) =
    self.xDataSource.value = replacedOwnedId(self.xDataSource.value, value.value)

  method numberOfItems*(self: NSComboBox): int =
    self.xObjectValues.len

  method objectValues*(self: NSComboBox): NSArray[NSString] =
    nsArray[NSString](self.xObjectValues)

  method itemObjectValueAtIndex*(self: NSComboBox, index: int): NSString =
    if index < 0 or index >= self.xObjectValues.len:
      return NSString(value: nil)
    retain(self.xObjectValues[index])

  method indexOfItemWithObjectValue*(self: NSComboBox, value: NSObject): int =
    if value.isNil:
      return -1
    let needle =
      if value.isKindOfClass(NSString):
        $value.NSString
      elif value.isKindOfClass(NSAttributedString):
        $value.NSAttributedString.string()
      else:
        return -1
    for idx, candidate in self.xObjectValues:
      if $candidate == needle:
        return idx
    -1

  method addItemWithObjectValue*(self: NSComboBox, value: NSObject) =
    if value.isNil:
      return
    if value.isKindOfClass(NSString):
      self.xObjectValues.add(value.NSString)
    else:
      self.xObjectValues.add(ns($value))
    self.noteNumberOfItemsChanged()

  method addItemsWithObjectValues*(self: NSComboBox, values: NSArray[NSObject]) =
    for item in values:
      self.addItemWithObjectValue(item)

  method removeAllItems*(self: NSComboBox) =
    self.xObjectValues = @[]
    self.xSelectedIndex = -1
    self.closePopup()
    self.setStringValue(@ns"")
    self.noteNumberOfItemsChanged()

  method removeItemAtIndex*(self: NSComboBox, index: int) =
    if index < 0 or index >= self.xObjectValues.len:
      return
    self.xObjectValues.del(index)
    if self.xObjectValues.len == 0:
      self.xSelectedIndex = -1
      self.closePopup()
      self.setStringValue(@ns"")
    elif self.xSelectedIndex == index:
      let nextIdx = min(index, self.xObjectValues.len - 1)
      self.selectItemAtIndex(nextIdx)
    elif index < self.xSelectedIndex:
      dec self.xSelectedIndex
    self.noteNumberOfItemsChanged()

  method removeItemWithObjectValue*(self: NSComboBox, value: NSObject) =
    let idx = self.indexOfItemWithObjectValue(value)
    if idx >= 0:
      self.removeItemAtIndex(idx)

  method insertItemWithObjectValue*(
      self: NSComboBox, value: NSObject, index {.kw("atIndex").}: int
  ) =
    if value.isNil:
      return
    let boundedIndex =
      if index < 0:
        0
      elif index > self.xObjectValues.len:
        self.xObjectValues.len
      else:
        index
    var objectValue = NSString(value: nil)
    if value.isKindOfClass(NSString):
      objectValue = value.NSString
    else:
      objectValue = ns($value)
    self.xObjectValues.insert(objectValue, boundedIndex)
    if self.xSelectedIndex >= boundedIndex:
      inc self.xSelectedIndex
    self.noteNumberOfItemsChanged()

  method indexOfSelectedItem*(self: NSComboBox): int =
    self.xSelectedIndex = -1
    let currentValue = self.stringValue()
    if currentValue.isNil:
      return -1
    let needle = $currentValue
    for idx, candidate in self.xObjectValues:
      if $candidate == needle:
        self.xSelectedIndex = idx
        return idx
    -1

  method hitTest*(self: NSComboBox, point: NSPoint): NSView =
    if self.isHiddenOrHasHiddenAncestor():
      return NSView(value: nil)
    if self.mouse(point, inRect = self.bounds()):
      return self.NSView
    NSView(value: nil)

  method objectValueOfSelectedItem*(self: NSComboBox): NSString =
    let idx = self.indexOfSelectedItem()
    if idx < 0:
      return NSString(value: nil)
    retain(self.xObjectValues[idx])

  method selectItemAtIndex*(self: NSComboBox, index: int) =
    if index < 0 or index >= self.xObjectValues.len:
      return
    self.setStringValue(self.xObjectValues[index])

  method selectItemWithObjectValue*(self: NSComboBox, value: NSObject) =
    let idx = self.indexOfItemWithObjectValue(value)
    self.selectItemAtIndex(idx)

  method deselectItemAtIndex*(self: NSComboBox, index: int) =
    if self.xSelectedIndex != index:
      return
    self.xSelectedIndex = -1
    self.xPopupHoveredIndex = -1
    self.setStringValue(@ns"")

  method openPopup*(self: NSComboBox) =
    if self.numberOfItems() <= 0:
      self.closePopup()
      return
    let popup = self.ensurePopupWindow()
    if popup.isNil:
      self.closePopup()
      return
    self.configurePopupWindow(popup)
    popup.makeKeyAndOrderFront(self.NSObject)
    self.setNeedsDisplay(true)

  method closePopup*(self: NSComboBox) =
    self.closePopupWindow()
    self.xPopupOpen = false
    self.xPopupHoveredIndex = -1
    self.setNeedsDisplay(true)

  method togglePopup*(self: NSComboBox) =
    if self.xPopupOpen:
      self.closePopup()
      return
    self.openPopup()

  method mouseDown*(self: NSComboBox, event: NSEvent) =
    if self.isNil or event.isNil or not self.isEnabled():
      return
    let localPoint =
      self.NSView.convertPoint(event.locationInWindow(), NSView(value: nil))
    if not comboBoxArrowZoneRect(self.bounds()).contains(localPoint.x, localPoint.y):
      callSuperVoid(self, getSelector("mouseDown:"), event)
      return
    if self.numberOfItems() <= 0:
      return

    self.xButtonPressed = true
    self.setNeedsDisplay(true)
    let firstFollowup = self.window().nextEventMatchingMask(
        NSLeftMouseUpMask + NSLeftMouseDraggedMask,
        referenceTimestampNow() + ComboBoxTrackingMaxWaitSeconds,
        @ns"NSDefaultRunLoopMode",
        true,
      )
    if not firstFollowup.isNil:
      let followupPoint =
        self.NSView.convertPoint(firstFollowup.locationInWindow(), NSView(value: nil))
      if firstFollowup.`type`() == NSLeftMouseUp and
          comboBoxArrowZoneRect(self.bounds()).contains(
            followupPoint.x, followupPoint.y
          ):
        self.xButtonPressed = false
        self.setNeedsDisplay(true)
        self.togglePopup()
        return
      self.window().postEvent(firstFollowup, true)
    let selectedIndex = self.trackPopupWithEvent(event)
    self.xButtonPressed = false
    self.setNeedsDisplay(true)
    if selectedIndex >= 0:
      self.activateItemAtIndex(selectedIndex)

  method mouseMoved*(self: NSComboBox, event: NSEvent) =
    discard

  method mouseDragged*(self: NSComboBox, event: NSEvent) =
    discard

  method mouseUp*(self: NSComboBox, event: NSEvent) =
    discard

  method activateItemAtIndex*(self: NSComboBox, index: int) =
    if index < 0 or index >= self.numberOfItems():
      return
    self.selectItemAtIndex(index)
    let control = self.NSControl
    discard control.sendAction(control.action(), control.target())

  method scrollItemAtIndexToTop*(self: NSComboBox, index: int) =
    discard

  method scrollItemAtIndexToVisible*(self: NSComboBox, index: int) =
    discard

  method noteNumberOfItemsChanged*(self: NSComboBox) =
    if self.xSelectedIndex >= self.xObjectValues.len:
      self.xSelectedIndex = -1
      self.setStringValue(@ns"")
    if self.xObjectValues.len == 0:
      self.closePopup()

  method reloadData*(self: NSComboBox) =
    discard

  method dealloc(self: NSComboBox) {.used.} =
    self.closePopupWindow()
    self.xObjectValues = @[]
    self.xDataSource.value = replacedOwnedId(self.xDataSource.value, nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSComboBox, self, getSelector("dealloc"))

objcImpl:
  method updateSelectionForEvent*(self: NSComboBoxWindow, event: NSEvent): int =
    if self.isNil or self.xView.isNil:
      return -1
    let index = self.xView.itemIndexForPoint(self.xView.pointInSelfForEvent(event))
    self.xView.setSelectedIndex(index)
    let comboBox = self.comboBox()
    if not comboBox.isNil:
      comboBox.setPopupHoveredIndex(index)
    self.xView.setNeedsDisplay(true)
    index

objcImpl:
  method mouseDown*(self: NSComboBoxView, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    let popup = self.window().NSComboBoxWindow
    if popup.isNil:
      return
    discard popup.updateSelectionForEvent(event)

  method mouseDragged*(self: NSComboBoxView, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    let popup = self.window().NSComboBoxWindow
    if popup.isNil:
      return
    discard popup.updateSelectionForEvent(event)

  method mouseMoved*(self: NSComboBoxView, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    let popup = self.window().NSComboBoxWindow
    if popup.isNil:
      return
    discard popup.updateSelectionForEvent(event)

  method mouseUp*(self: NSComboBoxView, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    let popup = self.window().NSComboBoxWindow
    if popup.isNil:
      return
    let index = popup.updateSelectionForEvent(event)
    let comboBox = popup.comboBox()
    if comboBox.isNil:
      return
    if index >= 0:
      comboBox.activateItemAtIndex(index)
    comboBox.closePopup()

proc new*(t: typedesc[NSComboBox]): NSComboBox =
  var allocated = NSComboBox.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSComboBoxView]): NSComboBoxView =
  var allocated = NSComboBoxView.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSComboBoxWindow]): NSComboBoxWindow =
  var allocated = NSComboBoxWindow.alloc()
  result = initOwned(move(allocated))

proc comboBoxPopupItemIndexAtPoint*(
    comboBox: auto, controlBox: NSRect, x: float32, y: float32
): int =
  let popupBox = comboBoxPopupFrame(comboBox, controlBox)
  if popupBox.size.width <= 0.0 or popupBox.size.height <= 0.0:
    return -1
  if not popupBox.contains(x, y):
    return -1
  let itemHeight = comboBoxPopupItemHeight(comboBox)
  if itemHeight <= 0.0:
    return -1
  let fromTop = popupBox.origin.y + popupBox.size.height - y - 1.0
  let visibleIndex = int(fromTop / itemHeight)
  if visibleIndex < 0 or visibleIndex >= comboBoxVisiblePopupItems(comboBox):
    return -1
  let itemIndex = comboBoxPopupFirstItemIndex(comboBox) + visibleIndex
  if itemIndex < 0 or itemIndex >= comboBox.numberOfItems():
    return -1
  itemIndex

proc refreshOpenComboBoxPopupsInView(view: NSView) =
  if view.isNil or view.isHidden():
    return
  if view.isKindOfClass(NSComboBox):
    let comboBox = view.NSComboBox
    if (not comboBox.isNil) and comboBox.popupOpen():
      let popup = comboBox.popupWindow()
      if not popup.isNil and not popup.windowClosed():
        comboBox.configurePopupWindow(popup)
  for child in view.subviews():
    refreshOpenComboBoxPopupsInView(child)

proc refreshOpenComboBoxPopups*(window: NSWindow) =
  if window.isNil:
    return
  let content = window.contentView()
  if content.isNil:
    return
  refreshOpenComboBoxPopupsInView(content)
