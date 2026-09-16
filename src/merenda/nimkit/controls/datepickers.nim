## Calendar dates, themed date pickers, and date-picker buttons.

import std/times

when defined(useNativeDynlib):
  from figdraw/dynlib import ZLevel
else:
  from figdraw import ZLevel

import sigils/core
import sigils/selectors

import ../accessibility/accessibility
import ../app/windows
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/views
import ./buttons

type
  CalendarDate* = object
    year*: int
    month*: int
    day*: int

  DatePickerSelectionHandler* = proc(date: CalendarDate) {.closure.}

  DatePicker* = ref object of View
    xDisplayedMonth: CalendarDate
    xSelectedDate: CalendarDate
    xHasSelectedDate: bool
    xTrackingDate: CalendarDate
    xHasTrackingDate: bool
    xOnSelect: DatePickerSelectionHandler

  DatePickerButton* = ref object of Button
    xTitlePrefix: string
    xSelectedDate: CalendarDate
    xHasSelectedDate: bool
    xDatePicker: DatePicker
    xPopupWindow: Window
    xPopupOpen: bool
    xPopupPresentation: PopupPresentation
    xOnSelect: DatePickerSelectionHandler

const
  DatePickerDefaultWidth* = 252.0'f32
  DatePickerDefaultHeight* = 244.0'f32
  CalendarGridLeft = 10.0'f32
  CalendarGridTop = 68.0'f32
  CalendarCellWidth = 33.0'f32
  CalendarCellHeight = 28.0'f32
  CalendarGridRows = 6
  CalendarGridColumns = 7
  CalendarHeaderHeight = 28.0'f32
  CalendarWeekdayTop = 44.0'f32

const
  MonthNames = [
    "January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December",
  ]
  WeekdayNames = ["S", "M", "T", "W", "T", "F", "S"]
  WeekdayOffsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]

func initCalendarDate*(year, month, day: int): CalendarDate =
  CalendarDate(year: year, month: month, day: day)

func isLeapYear*(year: int): bool =
  year mod 400 == 0 or (year mod 4 == 0 and year mod 100 != 0)

func daysInMonth*(date: CalendarDate): int =
  if date.month notin 1 .. 12:
    return 0
  case date.month
  of 2:
    if date.year.isLeapYear(): 29 else: 28
  of 4, 6, 9, 11:
    30
  else:
    31

func isValidCalendarDate*(date: CalendarDate): bool =
  date.month in 1 .. 12 and date.day >= 1 and date.day <= date.daysInMonth()

func weekday*(date: CalendarDate): int =
  ## Returns Sunday as 0 and Saturday as 6.
  if not date.isValidCalendarDate():
    return 0
  var year = date.year
  if date.month < 3:
    dec year
  (
    year + year div 4 - year div 100 + year div 400 + WeekdayOffsets[date.month - 1] +
    date.day
  ) mod 7

func `==`*(left, right: CalendarDate): bool =
  left.year == right.year and left.month == right.month and left.day == right.day

func `<`*(left, right: CalendarDate): bool =
  left.year < right.year or (
    left.year == right.year and
    (left.month < right.month or (left.month == right.month and left.day < right.day))
  )

func `<=`*(left, right: CalendarDate): bool =
  left < right or left == right

func dateByAddingMonths(date: CalendarDate, delta: int): CalendarDate =
  let absoluteMonth = date.year * 12 + date.month - 1 + delta
  initCalendarDate(absoluteMonth div 12, absoluteMonth mod 12 + 1, 1)

func formatCalendarDate*(date: CalendarDate): string =
  if not date.isValidCalendarDate():
    return ""
  MonthNames[date.month - 1][0 .. 2] & " " & (if date.day < 10: "0" else: "") & $date.day &
    ", " & $date.year

func formatCalendarMonth*(date: CalendarDate): string =
  if date.month notin 1 .. 12:
    return ""
  MonthNames[date.month - 1] & " " & $date.year

proc todayCalendarDate*(): CalendarDate =
  let current = now()
  initCalendarDate(current.year, current.month.ord, current.monthday)

func datePickerDefaultSize*(): Size =
  initSize(DatePickerDefaultWidth, DatePickerDefaultHeight)

proc datePickerStyleContext(
    picker: DatePicker, states: set[WidgetState] = {}
): StyleContext =
  controlStyle(srDatePicker, states, id = picker.styleId, classes = picker.styleClasses)

proc selectDate*(picker: DatePicker, date: CalendarDate) {.discardable.}
proc openPopup*(button: DatePickerButton)
proc closePopup*(button: DatePickerButton)
proc updateDateButtonTitle(button: DatePickerButton)
proc ownerWindow(button: DatePickerButton): Window

proc selectedDate*(picker: DatePicker): CalendarDate =
  picker.xSelectedDate

proc `selectedDate=`*(picker: DatePicker, date: CalendarDate) =
  if not date.isValidCalendarDate():
    return
  picker.xSelectedDate = date
  picker.xHasSelectedDate = true
  picker.xDisplayedMonth = initCalendarDate(date.year, date.month, 1)
  picker.needsDisplay = true

proc hasSelectedDate*(picker: DatePicker): bool =
  picker.xHasSelectedDate

proc `hasSelectedDate=`*(picker: DatePicker, value: bool) =
  if value and not picker.xSelectedDate.isValidCalendarDate():
    picker.xSelectedDate = todayCalendarDate()
  if picker.xHasSelectedDate == value:
    return
  picker.xHasSelectedDate = value
  picker.needsDisplay = true

proc displayedMonth*(picker: DatePicker): CalendarDate =
  picker.xDisplayedMonth

proc `displayedMonth=`*(picker: DatePicker, date: CalendarDate) =
  if date.month notin 1 .. 12:
    return
  let next = initCalendarDate(date.year, date.month, 1)
  if picker.xDisplayedMonth == next:
    return
  picker.xDisplayedMonth = next
  picker.needsDisplay = true

proc onSelect*(picker: DatePicker): DatePickerSelectionHandler =
  picker.xOnSelect

proc `onSelect=`*(picker: DatePicker, handler: DatePickerSelectionHandler) =
  picker.xOnSelect = handler

func datePickerSelectedState(picker: DatePicker, date: CalendarDate): set[WidgetState] =
  if picker.xHasSelectedDate and date == picker.xSelectedDate:
    {ssSelected}
  else:
    {}

protocol DatePickerDrawing of ViewDrawingProtocol:
  method draw(picker: DatePicker, context: DrawContext) =
    let
      bounds = picker.bounds()
      baseContext = picker.datePickerStyleContext()
      baseStyle = context.appearance.resolveBoxStyle(baseContext)
      selectedStyle =
        context.appearance.resolveBoxStyle(picker.datePickerStyleContext({ssSelected}))
      boundsFrame = context.renderRectFor(bounds)
    var mutedColor = baseStyle.text.color
    mutedColor.a *= 0.62'f32

    discard context.addRenderRectangle(
      boundsFrame,
      baseStyle.box.fill,
      baseStyle.box.borderColor,
      baseStyle.box.borderWidth,
      baseStyle.box.cornerRadius,
      baseStyle.box.shadows,
      maskContent = true,
      cornerRadii = baseStyle.box.cornerRadii,
    )

    let headerTextRect =
      rect(36.0, 8.0, max(bounds.size.width - 92.0'f32, 0.0'f32), CalendarHeaderHeight)
    context.addText(
      headerTextRect,
      picker.xDisplayedMonth.formatCalendarMonth(),
      baseStyle.text,
      taCenter,
    )
    context.addText(
      rect(10.0, 8.0, 26.0, CalendarHeaderHeight), "<", mutedColor, taCenter
    )
    context.addText(
      rect(bounds.size.width - 36.0'f32, 8.0, 26.0, CalendarHeaderHeight),
      ">",
      mutedColor,
      taCenter,
    )

    for column, name in WeekdayNames:
      let weekdayRect = rect(
        CalendarGridLeft + column.float32 * CalendarCellWidth,
        CalendarWeekdayTop,
        CalendarCellWidth,
        20.0,
      )
      context.addText(weekdayRect, name, mutedColor, taCenter)

    let firstWeekday = picker.xDisplayedMonth.weekday()
    for row in 0 ..< CalendarGridRows:
      for column in 0 ..< CalendarGridColumns:
        let day = row * CalendarGridColumns + column - firstWeekday + 1
        if day >= 1 and day <= picker.xDisplayedMonth.daysInMonth():
          let
            dayRect = rect(
              CalendarGridLeft + column.float32 * CalendarCellWidth,
              CalendarGridTop + row.float32 * CalendarCellHeight,
              CalendarCellWidth,
              CalendarCellHeight,
            )
            date = initCalendarDate(
              picker.xDisplayedMonth.year, picker.xDisplayedMonth.month, day
            )
            states = picker.datePickerSelectedState(date)
          var dayStyle = baseStyle.text
          if ssSelected in states:
            let center = initPoint(
              dayRect.origin.x + dayRect.size.width / 2.0'f32,
              dayRect.origin.y + dayRect.size.height / 2.0'f32,
            )
            discard context.addRenderCircle(
              center, fill(selectedStyle.box.borderColor), 12.0'f32
            )
            discard context.addRenderCircle(center, selectedStyle.box.fill, 11.0'f32)
            dayStyle = selectedStyle.text
          context.addText(dayRect, $day, dayStyle, taCenter)

protocol DatePickerPopupDrawing of ViewDrawingProtocol:
  method drawLevel(picker: DatePicker): ZLevel =
    PopupDrawLevel

protocol DatePickerPopupHitTesting of ViewProtocol:
  method hitTestLevel(picker: DatePicker, point: Point): int =
    discard point
    PopupDrawLevel.int

protocol DatePickerLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(picker: DatePicker): IntrinsicSize =
    initIntrinsicSize(datePickerDefaultSize())

func dateAtPoint(picker: DatePicker, point: Point): CalendarDate =
  let
    gridWidth = CalendarCellWidth * CalendarGridColumns.float32
    gridHeight = CalendarCellHeight * CalendarGridRows.float32
  if point.x < CalendarGridLeft or point.x >= CalendarGridLeft + gridWidth or
      point.y < CalendarGridTop or point.y >= CalendarGridTop + gridHeight:
    return
  let
    column = int((point.x - CalendarGridLeft) / CalendarCellWidth)
    row = int((point.y - CalendarGridTop) / CalendarCellHeight)
    day = row * CalendarGridColumns + column - picker.xDisplayedMonth.weekday() + 1
  if day >= 1 and day <= picker.xDisplayedMonth.daysInMonth():
    result =
      initCalendarDate(picker.xDisplayedMonth.year, picker.xDisplayedMonth.month, day)

protocol DatePickerEvents of ResponderEventProtocol:
  method mouseDown(picker: DatePicker, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false

    let bounds = picker.bounds()
    if rect(8.0, 6.0, 28.0, 28.0).contains(event.location):
      picker.xHasTrackingDate = false
      picker.displayedMonth = picker.displayedMonth.dateByAddingMonths(-1)
      return true
    if rect(bounds.size.width - 36.0'f32, 6.0, 28.0, 28.0).contains(event.location):
      picker.xHasTrackingDate = false
      picker.displayedMonth = picker.displayedMonth.dateByAddingMonths(1)
      return true

    let date = picker.dateAtPoint(event.location)
    picker.xTrackingDate = date
    picker.xHasTrackingDate = date.isValidCalendarDate()
    true

  method mouseDragged(picker: DatePicker, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    let date = picker.dateAtPoint(event.location)
    picker.xTrackingDate = date
    picker.xHasTrackingDate = date.isValidCalendarDate()
    true

  method mouseUp(picker: DatePicker, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    let date = picker.dateAtPoint(event.location)
    let shouldSelect = picker.xHasTrackingDate and date == picker.xTrackingDate
    picker.xHasTrackingDate = false
    if shouldSelect:
      picker.selectDate(date)
    true

  method keyDown(picker: DatePicker, event: KeyEvent): bool =
    case event.key
    of keyArrowLeft:
      picker.displayedMonth = picker.displayedMonth.dateByAddingMonths(-1)
      true
    of keyArrowRight:
      picker.displayedMonth = picker.displayedMonth.dateByAddingMonths(1)
      true
    else:
      false

protocol DatePickerAccessibility of AccessibilityProtocol:
  method accessibilityRole(picker: DatePicker): AccessibilityRole =
    arGroup

  method accessibilityLabel(picker: DatePicker): string =
    if picker.xAccessibilityLabel.len > 0: picker.xAccessibilityLabel else: "Date picker"

  method accessibilityValue(picker: DatePicker): string =
    if picker.xHasSelectedDate:
      picker.xSelectedDate.formatCalendarDate()
    else:
      "No date selected"

  method isAccessibilityElement(picker: DatePicker): bool =
    true

proc initDatePickerFields*(
    picker: DatePicker,
    selectedDate: CalendarDate,
    hasSelectedDate = true,
    frame: Rect = AutoRect,
) =
  initViewFields(picker, frame)
  picker.xSelectedDate =
    if selectedDate.isValidCalendarDate():
      selectedDate
    else:
      todayCalendarDate()
  picker.xHasSelectedDate = hasSelectedDate
  picker.xHasTrackingDate = false
  picker.xDisplayedMonth =
    initCalendarDate(picker.xSelectedDate.year, picker.xSelectedDate.month, 1)
  picker.acceptsFirstResponder = true
  picker.accessibilityRole = arGroup
  picker.accessibilityLabel = "Date picker"
  discard picker.withProtocol(DatePickerDrawing)
  discard picker.withProtocol(DatePickerPopupDrawing)
  discard picker.withProtocol(DatePickerPopupHitTesting)
  discard picker.withProtocol(DatePickerLayout)
  discard picker.withProtocol(DatePickerEvents)
  discard picker.withProtocol(DatePickerAccessibility)
  picker.applyInitialFrame(frame)

proc newDatePicker*(
    selectedDate: CalendarDate, hasSelectedDate = true, frame: Rect = AutoRect
): DatePicker =
  result = DatePicker()
  result.initDatePickerFields(selectedDate, hasSelectedDate, frame)

proc newDatePicker*(frame: Rect = AutoRect): DatePicker =
  newDatePicker(todayCalendarDate(), hasSelectedDate = false, frame = frame)

proc selectDate*(picker: DatePicker, date: CalendarDate) {.discardable.} =
  if not date.isValidCalendarDate():
    return
  picker.xHasTrackingDate = false
  picker.xSelectedDate = date
  picker.xHasSelectedDate = true
  picker.xDisplayedMonth = initCalendarDate(date.year, date.month, 1)
  picker.needsDisplay = true
  picker.postAccessibilityNotification(anValueChanged)
  if not picker.xOnSelect.isNil:
    picker.xOnSelect(date)

proc titlePrefix*(button: DatePickerButton): string =
  button.xTitlePrefix

proc `titlePrefix=`*(button: DatePickerButton, value: string) =
  if button.xTitlePrefix == value:
    return
  button.xTitlePrefix = value
  button.updateDateButtonTitle()

proc selectedDate*(button: DatePickerButton): CalendarDate =
  button.xSelectedDate

proc `selectedDate=`*(button: DatePickerButton, date: CalendarDate) =
  if not date.isValidCalendarDate():
    return
  button.xSelectedDate = date
  button.xHasSelectedDate = true
  button.updateDateButtonTitle()
  if not button.xDatePicker.isNil:
    button.xDatePicker.selectedDate = date
  button.postAccessibilityNotification(anValueChanged)

proc hasSelectedDate*(button: DatePickerButton): bool =
  button.xHasSelectedDate

proc `hasSelectedDate=`*(button: DatePickerButton, value: bool) =
  if value and not button.xSelectedDate.isValidCalendarDate():
    button.xSelectedDate = todayCalendarDate()
  if button.xHasSelectedDate == value:
    return
  button.xHasSelectedDate = value
  button.updateDateButtonTitle()
  if not button.xDatePicker.isNil:
    button.xDatePicker.hasSelectedDate = value
  button.postAccessibilityNotification(anValueChanged)

proc onSelect*(button: DatePickerButton): DatePickerSelectionHandler =
  button.xOnSelect

proc `onSelect=`*(button: DatePickerButton, handler: DatePickerSelectionHandler) =
  button.xOnSelect = handler

proc datePicker*(button: DatePickerButton): DatePicker =
  button.xDatePicker

proc popupWindow*(button: DatePickerButton): Window =
  button.xPopupWindow

proc popupOpen*(button: DatePickerButton): bool =
  button.xPopupOpen

proc popupPresentation*(button: DatePickerButton): PopupPresentation =
  button.xPopupPresentation

proc effectivePopupPresentation*(button: DatePickerButton): PopupPresentation =
  let owner = button.ownerWindow()
  if owner.isNil:
    return ppInline
  owner.resolvedPopupPresentation(button.xPopupPresentation)

proc `popupPresentation=`*(button: DatePickerButton, value: PopupPresentation) =
  if button.xPopupPresentation == value:
    return
  let wasOpen = button.xPopupOpen
  if wasOpen:
    button.closePopup()
  button.xPopupPresentation = value
  if wasOpen:
    button.openPopup()

proc `popupOpen=`*(button: DatePickerButton, value: bool) =
  if value:
    button.openPopup()
  else:
    button.closePopup()

proc updateDateButtonTitle(button: DatePickerButton) =
  button.title =
    if button.xHasSelectedDate:
      button.xTitlePrefix & " · " & button.xSelectedDate.formatCalendarDate()
    else:
      button.xTitlePrefix & " · Any date"

proc ownerWindow(button: DatePickerButton): Window =
  let owner = button.window()
  if owner of Window:
    result = Window(owner)

proc inlinePopupFrame(button: DatePickerButton, parent: View, size: Size): Rect =
  let
    anchor = button.rectToView(button.bounds(), parent)
    bounds = parent.bounds()
    maximumX = max(bounds.maxX - size.width, bounds.origin.x)
    x = min(max(anchor.origin.x, bounds.origin.x), maximumX)
    belowY = anchor.maxY
    aboveY = anchor.origin.y - size.height
    y =
      if belowY + size.height <= bounds.maxY or aboveY < bounds.origin.y:
        belowY
      else:
        aboveY
  rect(x, y, size.width, size.height)

proc openInlinePopup(button: DatePickerButton, picker: DatePicker, size: Size) =
  let owner = button.ownerWindow()
  if owner.isNil or owner.contentView().isNil:
    return
  let parent = owner.contentView()
  picker.frame = button.inlinePopupFrame(parent, size)
  parent.addSubview(picker)
  picker.needsDisplay = true

proc clearPopupState(button: DatePickerButton) =
  if not button.xDatePicker.isNil and not button.xDatePicker.superview().isNil:
    button.xDatePicker.removeFromSuperview()
  button.xPopupOpen = false
  button.xPopupWindow = nil
  button.xDatePicker = nil
  button.setWidgetState(ssOpen, false)
  button.needsDisplay = true

proc dismissPopup(button: DatePickerButton, reason: DismissReason) =
  discard reason
  let popupWindow = button.xPopupWindow
  button.clearPopupState()
  if not popupWindow.isNil and not popupWindow.isClosed():
    popupWindow.close()

proc datePickerDidSelect(button: DatePickerButton, date: CalendarDate) =
  button.selectedDate = date
  button.closePopup()
  if not button.xOnSelect.isNil:
    button.xOnSelect(date)
  discard button.sendAction()

proc openPopup*(button: DatePickerButton) =
  if button.xPopupOpen or not button.isEnabled():
    return
  let owner = button.ownerWindow()
  if owner.isNil:
    return
  let size = datePickerDefaultSize()
  let picker = newDatePicker(
    button.xSelectedDate,
    hasSelectedDate = button.xHasSelectedDate,
    frame = rect(0.0, 0.0, size.width, size.height),
  )
  picker.onSelect = proc(date: CalendarDate) =
    button.datePickerDidSelect(date)

  var popupWindow: Window
  if button.effectivePopupPresentation() == ppWindow and owner.nativeReady:
    popupWindow =
      owner.newPopupWindow(button.rectToWindow(button.bounds()), size, "Date Picker")
    popupWindow.setContentView(picker)
    popupWindow.setInitialFirstResponder(picker)
    popupWindow.makeKeyAndOrderFront()
    popupWindow.ensureNativeWindow()
    if not popupWindow.nativeReady:
      popupWindow.close()
      popupWindow = nil
  if popupWindow.isNil:
    button.openInlinePopup(picker, size)

  button.xPopupOpen = true
  button.xPopupWindow = popupWindow
  button.xDatePicker = picker
  button.setWidgetState(ssOpen, true)
  button.needsDisplay = true
  if not popupWindow.isNil:
    popupWindow.setPopupDoneHandler(
      proc() =
        if button.xPopupWindow != popupWindow:
          return
        if owner.hasActiveTransientSession() and owner.transientWindow() == popupWindow:
          discard owner.dismissTransientSession(tdrNativeDone)
        else:
          button.clearPopupState()
    )
  owner.beginTransientSession(
    owner =
      if popupWindow.isNil:
        Responder(picker)
      else:
        Responder(button),
    transientWindow = popupWindow,
    restoreResponder = Responder(button),
    onDismiss = proc(reason: DismissReason) =
      button.dismissPopup(reason),
  )
  if popupWindow.isNil:
    discard owner.makeFirstResponder(picker)
  else:
    discard popupWindow.makeFirstResponder(picker)

proc closePopup*(button: DatePickerButton) =
  let
    owner = button.ownerWindow()
    popupWindow = button.xPopupWindow
  if not button.xPopupOpen and popupWindow.isNil:
    return
  button.clearPopupState()
  if not owner.isNil and owner.hasActiveTransientSession() and
      owner.transientWindow() == popupWindow:
    discard owner.endTransientSession()
  if not popupWindow.isNil and not popupWindow.isClosed():
    popupWindow.close()

protocol DatePickerButtonEvents of ResponderEventProtocol:
  method mouseDown(button: DatePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      button.cancelActivationFeedback()
      button.setHighlighted(true)
      return true

  method mouseDragged(button: DatePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      button.setHighlighted(button.pointInside(event.location))
      return true

  method mouseUp(button: DatePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      let clicked = button.pointInside(event.location)
      button.setHighlighted(false)
      if clicked:
        button.popupOpen = not button.popupOpen()
      return true

  method keyDown(button: DatePickerButton, event: KeyEvent): bool =
    if not button.isEnabled():
      return false
    case event.key
    of keyEnter, keySpace, keyArrowDown:
      button.openPopup()
      true
    of keyEscape:
      if button.popupOpen():
        button.closePopup()
        true
      else:
        false
    else:
      false

protocol DatePickerButtonAccessibility of AccessibilityProtocol:
  method accessibilityRole(button: DatePickerButton): AccessibilityRole =
    arPopupButton

  method accessibilityLabel(button: DatePickerButton): string =
    if button.xAccessibilityLabel.len > 0:
      button.xAccessibilityLabel
    else:
      button.title()

  method accessibilityValue(button: DatePickerButton): string =
    if button.xHasSelectedDate:
      button.xSelectedDate.formatCalendarDate()
    else:
      "No date selected"

  method accessibilityTraits(button: DatePickerButton): AccessibilityTraits =
    result = button.xAccessibilityTraits + {atButton}
    if not button.isEnabled():
      result.incl atDisabled
    if button.focused():
      result.incl atFocused

  method isAccessibilityElement(button: DatePickerButton): bool =
    true

  method accessibilityActionNames(button: DatePickerButton): seq[string] =
    @[AccessibilityActionShowMenu]

  method accessibilityPerformAction(button: DatePickerButton, action: string): bool =
    if action != AccessibilityActionShowMenu or not button.isEnabled():
      return false
    button.openPopup()
    true

proc initDatePickerButtonFields*(
    button: DatePickerButton,
    titlePrefix = "Date",
    selectedDate: CalendarDate = CalendarDate(),
    hasSelectedDate = false,
    frame: Rect = AutoRect,
) =
  initButtonFields(button, frame = frame)
  button.xTitlePrefix = titlePrefix
  button.xSelectedDate =
    if selectedDate.isValidCalendarDate():
      selectedDate
    else:
      todayCalendarDate()
  button.xHasSelectedDate = hasSelectedDate
  button.xPopupPresentation = ppAutomatic
  button.updateDateButtonTitle()
  discard button.withProtocol(DatePickerButtonEvents)
  discard button.withProtocol(DatePickerButtonAccessibility)

proc newDatePickerButton*(
    titlePrefix = "Date", frame: Rect = AutoRect
): DatePickerButton =
  result = DatePickerButton()
  result.initDatePickerButtonFields(titlePrefix, frame = frame)

proc newDatePickerButton*(
    titlePrefix: string, selectedDate: CalendarDate, frame: Rect = AutoRect
): DatePickerButton =
  result = DatePickerButton()
  result.initDatePickerButtonFields(
    titlePrefix, selectedDate, hasSelectedDate = true, frame = frame
  )
