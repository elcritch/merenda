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
    xScrollView: NSScrollView
    xClientView: NSView
    xAccessoryView: NSView
    xMeasurementUnits: NSString
    xOriginOffset: float32
    xRuleThickness: float32
    xThicknessForMarkers: float32
    xThicknessForAccessoryView: float32
    xOrientation: NSRulerOrientation
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
    discard x
    discard y
    discard width
    discard height
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
    result.xScrollView =
      if scrollView.isNil:
        NSScrollView(value: nil)
      else:
        retain(scrollView)
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
    discard self
    nsArray[NSObject](@[])

  method scrollView*(self: NSRulerView): NSScrollView =
    if self.xScrollView.isNil:
      return NSScrollView(value: nil)
    retain(self.xScrollView)

  method clientView*(self: NSRulerView): NSView =
    if self.xClientView.isNil:
      return NSView(value: nil)
    retain(self.xClientView)

  method accessoryView*(self: NSRulerView): NSView =
    if self.xAccessoryView.isNil:
      return NSView(value: nil)
    retain(self.xAccessoryView)

  method measurementUnits*(self: NSRulerView): NSString =
    if self.xMeasurementUnits.isNil:
      return @ns""
    retain(self.xMeasurementUnits)

  method orientation*(self: NSRulerView): NSRulerOrientation =
    self.xOrientation

  method ruleThickness*(self: NSRulerView): float32 =
    self.xRuleThickness

  method reservedThicknessForMarkers*(self: NSRulerView): float32 =
    self.xThicknessForMarkers

  method reservedThicknessForAccessoryView*(self: NSRulerView): float32 =
    self.xThicknessForAccessoryView

  method originOffset*(self: NSRulerView): float32 =
    self.xOriginOffset

  method baselineLocation*(self: NSRulerView): float32 =
    self.xRuleThickness

  method requiredThickness*(self: NSRulerView): float32 =
    result = self.xRuleThickness
    if self.xMarkerCount > 0:
      result += self.xThicknessForMarkers
    if not self.xAccessoryView.isNil:
      result += self.xThicknessForAccessoryView

  method setScrollView*(self: NSRulerView, scrollView: NSScrollView) =
    self.xScrollView =
      if scrollView.isNil:
        NSScrollView(value: nil)
      else:
        retain(scrollView)
    self.invalidateHashMarks()

  method setClientView*(self: NSRulerView, view: NSView) =
    self.xClientView =
      if view.isNil:
        NSView(value: nil)
      else:
        retain(view)
    self.xMarkerCount = 0
    self.invalidateHashMarks()
    requestScrollViewTile(self.xScrollView)

  method setAccessoryView*(self: NSRulerView, view: NSView) =
    self.xAccessoryView =
      if view.isNil:
        NSView(value: nil)
      else:
        retain(view)
    requestScrollViewTile(self.xScrollView)

  method setMarkers*(self: NSRulerView, markers: NSArray[NSObject]) =
    self.xMarkerCount = markers.len
    requestScrollViewTile(self.xScrollView)

  method addMarker*(self: NSRulerView, marker: NSObject) =
    discard marker
    inc self.xMarkerCount
    requestScrollViewTile(self.xScrollView)

  method removeMarker*(self: NSRulerView, marker: NSObject) =
    discard marker
    if self.xMarkerCount > 0:
      dec self.xMarkerCount
    requestScrollViewTile(self.xScrollView)

  method setMeasurementUnits*(self: NSRulerView, unitName: NSString) =
    self.xMeasurementUnits = unitName
    self.invalidateHashMarks()
    requestScrollViewTile(self.xScrollView)

  method setOrientation*(self: NSRulerView, orientation: NSRulerOrientation) =
    self.xOrientation = orientation

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
    discard self
    discard marker
    discard event
    false

  method moveRulerlineFromLocation*(
      self: NSRulerView, fromLocation: float32, toLocation {.kw("toLocation").}: float32
  ) =
    discard self
    discard fromLocation
    discard toLocation

  method invalidateHashMarks*(self: NSRulerView) =
    self.xHashMarksDirty = true
    self.setNeedsDisplay(true)

  method drawHashMarksAndLabelsInRect*(self: NSRulerView, rect: NSRect) =
    discard self
    discard rect

  method drawMarkersInRect*(self: NSRulerView, rect: NSRect) =
    discard self
    discard rect

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
  discard
  discard name
  discard abbreviation
  discard conversionFactor
  discard stepUpCycle
  discard stepDownCycle

proc new*(t: typedesc[NSRulerView]): NSRulerView =
  var allocated = NSRulerView.alloc()
  result = initOwned(move(allocated))
