import ./runtime
import ./views

const
  defaultRuleThickness = 16.0'f32
  defaultMarkerThickness = 15.0'f32

proc requestScrollViewTile(scrollView: NSScrollView) =
  if scrollView.isNil:
    return
  discard cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(
    scrollView.value, getSelector("tile")
  )

objcImpl:
  type NSRulerView* = object of NSView
    xScrollView {.get: scrollView.}: NSScrollView
    xClientView {.get: clientView.}: NSView
    xAccessoryView {.get: accessoryView.}: NSView
    xMeasurementUnits {.get: measurementUnits.}: NSString
    xOriginOffset {.get: originOffset.}: float32
    xRuleThickness {.get: ruleThickness.}: float32
    xThicknessForMarkers {.get: reservedThicknessForMarkers.}: float32
    xThicknessForAccessoryView {.get: reservedThicknessForAccessoryView.}: float32
    xOrientation {.set: setOrientation, get: orientation.}: NSRulerOrientation
    xMarkerCount: int
    xHashMarksDirty: bool

  method init*(self: var NSRulerView): NSRulerView =
    result = asTypeRaw[NSRulerView](
      cast[proc(
        self: IDPtr, op: SEL, scrollView: IDPtr, orientation: NSRulerOrientation
      ): IDPtr {.cdecl, varargs.}](objc_msgSend)(
        self.value,
        getSelector("initWithScrollView:orientation:"),
        nil,
        NSHorizontalRuler,
      )
    )

  method initWithFrame*(
      self: var NSRulerView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSRulerView =
    result = asTypeRaw[NSRulerView](
      cast[proc(
        self: IDPtr, op: SEL, scrollView: IDPtr, orientation: NSRulerOrientation
      ): IDPtr {.cdecl, varargs.}](objc_msgSend)(
        self.value,
        getSelector("initWithScrollView:orientation:"),
        nil,
        NSHorizontalRuler,
      )
    )
    if result.isNil:
      return
    result.setFrame(
      x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0)
    )

  method initWithScrollView*(
      self: var NSRulerView,
      scrollView: NSScrollView,
      orientation {.kw("orientation").}: NSRulerOrientation,
  ): NSRulerView =
    var frame = nsRect(0.0, 0.0, 1.0, 1.0)
    if not scrollView.isNil:
      frame = scrollView.frame()
    if orientation == NSHorizontalRuler:
      frame.size.height = defaultRuleThickness
    else:
      frame.size.width = defaultRuleThickness

    var superObj =
      ObjcSuper(receiver: self.value, superClass: getClass(NSRulerView).getSuperclass())
    result = asTypeRaw[NSRulerView](
      cast[proc(
        superObj: var ObjcSuper,
        op: SEL,
        x: float32,
        y: float32,
        width: float32,
        height: float32,
      ): IDPtr {.cdecl, varargs.}](objc_msgSendSuper)(
        superObj,
        getSelector("initWithFrame:y:width:height:"),
        frame.origin.x.float32,
        frame.origin.y.float32,
        frame.size.width.float32,
        frame.size.height.float32,
      )
    )
    if result.isNil:
      return
    result.xScrollView = retain(scrollView)
    result.xClientView = NSView(value: nil)
    result.xAccessoryView = NSView(value: nil)
    result.xMeasurementUnits = @ns"Inches"
    result.xOriginOffset = 0.0
    result.xRuleThickness = defaultRuleThickness
    result.xThicknessForMarkers = defaultMarkerThickness
    result.xThicknessForAccessoryView = 0.0
    result.xOrientation = orientation
    result.xMarkerCount = 0
    result.xHashMarksDirty = true

  method markers*(self: NSRulerView): NSArray[NSObject] =
    if self.xMarkerCount == 0:
      return nsArray[NSObject](@[])
    nsArray[NSObject](@[])

  method baselineLocation*(self: NSRulerView): float32 =
    self.xRuleThickness

  method requiredThickness*(self: NSRulerView): float32 =
    result = self.xRuleThickness
    if self.xMarkerCount > 0:
      result += self.xThicknessForMarkers
    if not self.xAccessoryView.isNil:
      result += self.xThicknessForAccessoryView

  method setScrollView*(self: NSRulerView, scrollView: NSScrollView) =
    self.xScrollView = retain(scrollView)
    self.invalidateHashMarks()

  method setClientView*(self: NSRulerView, view: NSView) =
    self.xClientView = retain(view)
    self.xMarkerCount = 0
    self.invalidateHashMarks()
    requestScrollViewTile(self.xScrollView)

  method setAccessoryView*(self: NSRulerView, view: NSView) =
    self.xAccessoryView = retain(view)
    requestScrollViewTile(self.xScrollView)

  method setMarkers*(self: NSRulerView, markers: NSArray[NSObject]) =
    self.xMarkerCount = markers.len
    requestScrollViewTile(self.xScrollView)

  method addMarker*(self: NSRulerView, marker: NSObject) =
    if marker.isNil:
      return
    inc self.xMarkerCount
    requestScrollViewTile(self.xScrollView)

  method removeMarker*(self: NSRulerView, marker: NSObject) =
    if marker.isNil:
      return
    if self.xMarkerCount > 0:
      dec self.xMarkerCount
    requestScrollViewTile(self.xScrollView)

  method setMeasurementUnits*(self: NSRulerView, unitName: NSString) =
    self.xMeasurementUnits = unitName
    self.invalidateHashMarks()
    requestScrollViewTile(self.xScrollView)

  method setRuleThickness*(self: NSRulerView, value: float32) =
    self.xRuleThickness = max(value, 0.0)
    requestScrollViewTile(self.xScrollView)

  method setReservedThicknessForMarkers*(self: NSRulerView, value: float32) =
    self.xThicknessForMarkers = max(value, 0.0)
    requestScrollViewTile(self.xScrollView)

  method setReservedThicknessForAccessoryView*(self: NSRulerView, value: float32) =
    self.xThicknessForAccessoryView = max(value, 0.0)
    requestScrollViewTile(self.xScrollView)

  method setOriginOffset*(self: NSRulerView, value: float32) =
    self.xOriginOffset = value
    self.invalidateHashMarks()

  method trackMarker*(
      self: NSRulerView, marker: NSObject, event {.kw("withMouseEvent").}: NSEvent
  ): bool =
    if self.xClientView.isNil:
      return false
    if marker.isNil or event.isNil:
      return false
    false

  method moveRulerlineFromLocation*(
      self: NSRulerView, fromLocation: float32, toLocation {.kw("toLocation").}: float32
  ) =
    if fromLocation != toLocation:
      self.invalidateHashMarks()

  method invalidateHashMarks*(self: NSRulerView) =
    self.xHashMarksDirty = true
    self.setNeedsDisplay(true)

  method drawHashMarksAndLabelsInRect*(self: NSRulerView, rect: NSRect) =
    if rect.size.width <= 0.0 or rect.size.height <= 0.0:
      return
    self.xHashMarksDirty = false

  method drawMarkersInRect*(self: NSRulerView, rect: NSRect) =
    if rect.size.width <= 0.0 or rect.size.height <= 0.0:
      return

  method dealloc(self: NSRulerView) {.used.} =
    self.xScrollView = NSScrollView(value: nil)
    self.xClientView = NSView(value: nil)
    self.xAccessoryView = NSView(value: nil)
    self.xMeasurementUnits = NSString(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSRulerView, self, getSelector("dealloc"))

proc registerUnitWithName*(
    t: typedesc[NSRulerView],
    name: NSString,
    abbreviation {.kw("abbreviation").}: NSString,
    conversionFactor {.kw("unitToPointsConversionFactor").}: float32,
    stepUpCycle {.kw("stepUpCycle").}: NSArray[NSObject],
    stepDownCycle {.kw("stepDownCycle").}: NSArray[NSObject],
) =
  if name.isNil or abbreviation.isNil:
    return
  if conversionFactor <= 0.0:
    return
  if stepUpCycle.isNil and stepDownCycle.isNil:
    return

proc new*(t: typedesc[NSRulerView]): NSRulerView =
  var allocated = NSRulerView.alloc()
  result = initOwned(move(allocated))
