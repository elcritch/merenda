## Calendar dates, themed date/time pickers, and picker buttons.

import std/[strutils, times]

from figdraw import ZLevel

import sigils/core
import sigils/selectors

import ../accessibility/accessibility
import ../app/windows
import ../drawing
import ../foundation/events
import ../foundation/objectvalues
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

  ## A wall-clock time without a date or timezone.
  ##
  ## ``ObjectTimeValue`` is used here so time pickers can be passed directly to
  ## NimKit's object-value APIs.
  TimeOfDay* = ObjectTimeValue
  ClockTime* = TimeOfDay
  CalendarTime* = TimeOfDay

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
    xPopupHost: PopupHost
    xPopupOpen: bool
    xPopupPresentation: PopupPresentation
    xOnSelect: DatePickerSelectionHandler

  TimePickerSelectionHandler* = proc(time: TimeOfDay) {.closure.}

  TimePickerPart = enum
    tppHour
    tppMinute
    tppSecond

  TimePicker* = ref object of View
    xSelectedTime: TimeOfDay
    xDraftTime: TimeOfDay
    xHasSelectedTime: bool
    xEditingPart: TimePickerPart
    xTrackingPart: TimePickerPart
    xTrackingDirection: int
    xHasTrackingPart: bool
    xTrackingDone: bool
    xOnSelect: TimePickerSelectionHandler

  TimePickerButton* = ref object of Button
    xTitlePrefix: string
    xSelectedTime: TimeOfDay
    xHasSelectedTime: bool
    xTimePicker: TimePicker
    xPopupHost: PopupHost
    xPopupOpen: bool
    xPopupPresentation: PopupPresentation
    xOnSelect: TimePickerSelectionHandler

  DateTimePickerSelectionHandler* = proc(value: DateTime) {.closure.}

  DateTimePicker* = ref object of View
    xSelectedDateTime: DateTime
    xDraftDateTime: DateTime
    xHasSelectedDateTime: bool
    xDatePicker: DatePicker
    xTimePicker: TimePicker
    xOnSelect: DateTimePickerSelectionHandler

  DateTimePickerButton* = ref object of Button
    xTitlePrefix: string
    xSelectedDateTime: DateTime
    xHasSelectedDateTime: bool
    xDateTimePicker: DateTimePicker
    xPopupHost: PopupHost
    xPopupOpen: bool
    xPopupPresentation: PopupPresentation
    xOnSelect: DateTimePickerSelectionHandler

const
  DatePickerDefaultWidth* = 252.0'f32
  DatePickerDefaultHeight* = 244.0'f32
  TimePickerDefaultWidth* = 252.0'f32
  TimePickerDefaultHeight* = 178.0'f32
  TimePickerColumnWidth = 68.0'f32
  TimePickerColumnGap = 5.0'f32
  TimePickerColumnLeft = 10.0'f32
  TimePickerHeaderHeight = 24.0'f32
  TimePickerLabelTop = 32.0'f32
  TimePickerValueTop = 51.0'f32
  TimePickerValueHeight = 32.0'f32
  TimePickerDoneLeft = 178.0'f32
  TimePickerDoneTop = 136.0'f32
  TimePickerDoneWidth = 64.0'f32
  TimePickerDoneHeight = 30.0'f32
  DateTimePickerDefaultWidth* = DatePickerDefaultWidth
  DateTimePickerDefaultHeight* = DatePickerDefaultHeight + TimePickerDefaultHeight
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
  if not button.xPopupHost.isNil:
    return button.xPopupHost.popupWindow()

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

proc clearPopupState(button: DatePickerButton, host: PopupHost = nil) =
  if not host.isNil and button.xPopupHost != host:
    return
  if not button.xDatePicker.isNil and not button.xDatePicker.superview().isNil:
    button.xDatePicker.removeFromSuperview()
  button.xPopupOpen = false
  button.xPopupHost = nil
  button.xDatePicker = nil
  button.setWidgetState(ssOpen, false)
  button.needsDisplay = true

proc dismissPopup(button: DatePickerButton, host: PopupHost, reason: DismissReason) =
  discard reason
  button.clearPopupState(host)

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

  button.xDatePicker = picker
  let host = newPopupHost(
    owner,
    button,
    picker,
    size,
    title = "Date Picker",
    presentation = button.xPopupPresentation,
    restoreResponder = Responder(button),
    onDismiss = proc(host: PopupHost, reason: DismissReason) =
      button.dismissPopup(host, reason),
  )
  button.xPopupHost = host
  if not host.presentPopup():
    button.clearPopupState(host)
    return

  button.xPopupOpen = true
  button.setWidgetState(ssOpen, true)
  button.needsDisplay = true

proc closePopup*(button: DatePickerButton) =
  let host = button.xPopupHost
  if not button.xPopupOpen and host.isNil:
    return
  if not host.isNil:
    discard host.dismissPopup()
  else:
    button.clearPopupState()

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

func initTimeOfDay*(hour, minute: int, second = 0, nanosecond = 0): TimeOfDay =
  initObjectTimeValue(hour, minute, second, nanosecond)

func initClockTime*(hour, minute: int, second = 0, nanosecond = 0): ClockTime =
  initTimeOfDay(hour, minute, second, nanosecond)

func initCalendarTime*(hour, minute: int, second = 0, nanosecond = 0): CalendarTime =
  initTimeOfDay(hour, minute, second, nanosecond)

func isValidTimeOfDay*(time: TimeOfDay): bool =
  time.hour in 0 .. 23 and time.minute in 0 .. 59 and time.second in 0 .. 59 and
    time.nanosecond in 0 .. 999_999_999

func isValidClockTime*(time: ClockTime): bool =
  time.isValidTimeOfDay()

func isValidTimeValue*(time: TimeOfDay): bool =
  time.isValidTimeOfDay()

func timeOfDayBefore(left, right: TimeOfDay): bool =
  left.hour < right.hour or (
    left.hour == right.hour and (
      left.minute < right.minute or (
        left.minute == right.minute and (
          left.second < right.second or
          (left.second == right.second and left.nanosecond < right.nanosecond)
        )
      )
    )
  )

func `<`*(left, right: TimeOfDay): bool =
  left.timeOfDayBefore(right)

func `<=`*(left, right: TimeOfDay): bool =
  left < right or left == right

func formatTimeOfDay*(time: TimeOfDay): string =
  if not time.isValidTimeOfDay():
    return ""
  align($time.hour, 2, '0') & ":" & align($time.minute, 2, '0') & ":" &
    align($time.second, 2, '0')

func formatClockTime*(time: ClockTime): string =
  time.formatTimeOfDay()

func formatTimeValue*(time: TimeOfDay): string =
  time.formatTimeOfDay()

proc currentTimeOfDay*(): TimeOfDay =
  let current = now()
  initTimeOfDay(current.hour, current.minute, current.second, current.nanosecond)

proc nowTimeOfDay*(): TimeOfDay =
  currentTimeOfDay()

proc timePickerDefaultSize*(): Size =
  initSize(TimePickerDefaultWidth, TimePickerDefaultHeight)

proc timePickerStyleContext(
    picker: TimePicker, states: set[WidgetState] = {}
): StyleContext =
  controlStyle(srDatePicker, states, id = picker.styleId, classes = picker.styleClasses)

proc selectTime*(picker: TimePicker, time: TimeOfDay) {.discardable.}
proc confirmTime*(picker: TimePicker): bool
proc openPopup*(button: TimePickerButton)
proc closePopup*(button: TimePickerButton)
proc updateTimeButtonTitle(button: TimePickerButton)
proc ownerWindow(button: TimePickerButton): Window

proc selectedTime*(picker: TimePicker): TimeOfDay =
  picker.xSelectedTime

proc `selectedTime=`*(picker: TimePicker, time: TimeOfDay) =
  if not time.isValidTimeOfDay():
    return
  picker.xSelectedTime = time
  picker.xDraftTime = time
  picker.xHasSelectedTime = true
  picker.needsDisplay = true

proc hasSelectedTime*(picker: TimePicker): bool =
  picker.xHasSelectedTime

proc `hasSelectedTime=`*(picker: TimePicker, value: bool) =
  if value and not picker.xDraftTime.isValidTimeOfDay():
    picker.xDraftTime = currentTimeOfDay()
  if picker.xHasSelectedTime == value:
    return
  picker.xHasSelectedTime = value
  picker.needsDisplay = true

proc onSelect*(picker: TimePicker): TimePickerSelectionHandler =
  picker.xOnSelect

proc `onSelect=`*(picker: TimePicker, handler: TimePickerSelectionHandler) =
  picker.xOnSelect = handler

func timePickerPartLabel(part: TimePickerPart): string =
  case part
  of tppHour: "Hour"
  of tppMinute: "Minute"
  of tppSecond: "Second"

func timePickerPartValue(time: TimeOfDay, part: TimePickerPart): int =
  case part
  of tppHour: time.hour
  of tppMinute: time.minute
  of tppSecond: time.second

func timePickerColumnX(part: TimePickerPart): float32 =
  TimePickerColumnLeft +
    ord(part).float32 * (TimePickerColumnWidth + TimePickerColumnGap)

func timePickerColumnContains(part: TimePickerPart, point: Point): bool =
  let x = part.timePickerColumnX()
  point.x >= x and point.x < x + TimePickerColumnWidth

proc timePickerDoneRect(picker: TimePicker): Rect =
  rect(
    max(picker.bounds().size.width - TimePickerDoneWidth - 10.0'f32, TimePickerDoneLeft),
    TimePickerDoneTop,
    TimePickerDoneWidth,
    TimePickerDoneHeight,
  )

func timePickerPartAtX(point: Point, part: var TimePickerPart): bool =
  for candidate in TimePickerPart:
    if candidate.timePickerColumnContains(point):
      part = candidate
      return true

func timePickerControlAtPoint(
    picker: TimePicker, point: Point, part: var TimePickerPart, direction: var int
): bool =
  if not point.timePickerPartAtX(part):
    return false
  if point.y >= TimePickerValueTop - 18.0'f32 and point.y < TimePickerValueTop:
    direction = 1
    return true
  if point.y > TimePickerValueTop + TimePickerValueHeight and
      point.y <= TimePickerValueTop + TimePickerValueHeight + 18.0'f32:
    direction = -1
    return true
  false

proc adjustTimePart(time: var TimeOfDay, part: TimePickerPart, delta: int) =
  case part
  of tppHour:
    time.hour = (time.hour + delta) mod 24
    if time.hour < 0:
      time.hour += 24
  of tppMinute:
    time.minute = (time.minute + delta) mod 60
    if time.minute < 0:
      time.minute += 60
  of tppSecond:
    time.second = (time.second + delta) mod 60
    if time.second < 0:
      time.second += 60

proc updateDraftTime(picker: TimePicker, part: TimePickerPart, delta: int) =
  picker.xEditingPart = part
  picker.xDraftTime.adjustTimePart(part, delta)
  picker.needsDisplay = true

func timePickerSelectedState(
    picker: TimePicker, part: TimePickerPart
): set[WidgetState] =
  if picker.xEditingPart == part:
    {ssSelected}
  else:
    {}

protocol TimePickerDrawing of ViewDrawingProtocol:
  method draw(picker: TimePicker, context: DrawContext) =
    let
      bounds = picker.bounds()
      baseContext = picker.timePickerStyleContext()
      baseStyle = context.appearance.resolveBoxStyle(baseContext)
      selectedStyle =
        context.appearance.resolveBoxStyle(picker.timePickerStyleContext({ssSelected}))
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

    context.addText(
      rect(10.0, 7.0, bounds.size.width - 20.0'f32, TimePickerHeaderHeight),
      if picker.xHasSelectedTime:
        picker.xDraftTime.formatTimeOfDay()
      else:
        "Select a time",
      baseStyle.text,
      taCenter,
    )

    for part in TimePickerPart:
      let
        x = part.timePickerColumnX()
        valueRect =
          rect(x, TimePickerValueTop, TimePickerColumnWidth, TimePickerValueHeight)
        states = picker.timePickerSelectedState(part)
      var valueStyle = baseStyle.text
      if ssSelected in states:
        discard context.addRenderRectangle(
          context.renderRectFor(valueRect),
          selectedStyle.box.fill,
          selectedStyle.box.borderColor,
          selectedStyle.box.borderWidth,
          selectedStyle.box.cornerRadius,
          selectedStyle.box.shadows,
          cornerRadii = selectedStyle.box.cornerRadii,
        )
        valueStyle = selectedStyle.text
      context.addText(
        rect(x, TimePickerLabelTop, TimePickerColumnWidth, 18.0),
        part.timePickerPartLabel(),
        mutedColor,
        taCenter,
      )
      context.addText(
        rect(x, TimePickerValueTop - 18.0'f32, TimePickerColumnWidth, 18.0),
        "▲",
        mutedColor,
        taCenter,
      )
      context.addText(
        valueRect, $picker.xDraftTime.timePickerPartValue(part), valueStyle, taCenter
      )
      context.addText(
        rect(x, TimePickerValueTop + TimePickerValueHeight, TimePickerColumnWidth, 18.0),
        "▼",
        mutedColor,
        taCenter,
      )

    let doneRect = picker.timePickerDoneRect()
    discard context.addRenderRectangle(
      context.renderRectFor(doneRect),
      selectedStyle.box.fill,
      selectedStyle.box.borderColor,
      selectedStyle.box.borderWidth,
      selectedStyle.box.cornerRadius,
      selectedStyle.box.shadows,
      cornerRadii = selectedStyle.box.cornerRadii,
    )
    context.addText(doneRect, "Done", selectedStyle.text, taCenter)

protocol TimePickerPopupDrawing of ViewDrawingProtocol:
  method drawLevel(picker: TimePicker): ZLevel =
    PopupDrawLevel

protocol TimePickerPopupHitTesting of ViewProtocol:
  method hitTestLevel(picker: TimePicker, point: Point): int =
    discard point
    PopupDrawLevel.int

protocol TimePickerLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(picker: TimePicker): IntrinsicSize =
    initIntrinsicSize(timePickerDefaultSize())

protocol TimePickerEvents of ResponderEventProtocol:
  method mouseDown(picker: TimePicker, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    picker.xHasTrackingPart = false
    picker.xTrackingDone = picker.timePickerDoneRect().contains(event.location)
    if picker.xTrackingDone:
      return true
    var part: TimePickerPart
    if event.location.timePickerPartAtX(part):
      picker.xEditingPart = part
    var direction: int
    if picker.timePickerControlAtPoint(event.location, part, direction):
      picker.xTrackingPart = part
      picker.xTrackingDirection = direction
      picker.xHasTrackingPart = true
    true

  method mouseDragged(picker: TimePicker, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    true

  method mouseUp(picker: TimePicker, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    let
      wasDone = picker.xTrackingDone
      done = picker.timePickerDoneRect().contains(event.location)
    picker.xTrackingDone = false
    if wasDone:
      if done:
        discard picker.confirmTime()
      return true

    if picker.xHasTrackingPart:
      var part: TimePickerPart
      var direction: int
      let control = picker.timePickerControlAtPoint(event.location, part, direction)
      if control and part == picker.xTrackingPart and
          direction == picker.xTrackingDirection:
        picker.updateDraftTime(part, direction)
    picker.xHasTrackingPart = false
    true

  method keyDown(picker: TimePicker, event: KeyEvent): bool =
    case event.key
    of keyArrowLeft:
      if ord(picker.xEditingPart) > ord(low(TimePickerPart)):
        dec picker.xEditingPart
      picker.needsDisplay = true
      true
    of keyArrowRight:
      if ord(picker.xEditingPart) < ord(high(TimePickerPart)):
        inc picker.xEditingPart
      picker.needsDisplay = true
      true
    of keyArrowUp:
      picker.updateDraftTime(picker.xEditingPart, 1)
      true
    of keyArrowDown:
      picker.updateDraftTime(picker.xEditingPart, -1)
      true
    of keyEnter, keySpace:
      picker.confirmTime()
    else:
      false

protocol TimePickerAccessibility of AccessibilityProtocol:
  method accessibilityRole(picker: TimePicker): AccessibilityRole =
    arGroup

  method accessibilityLabel(picker: TimePicker): string =
    if picker.xAccessibilityLabel.len > 0: picker.xAccessibilityLabel else: "Time picker"

  method accessibilityValue(picker: TimePicker): string =
    if picker.xHasSelectedTime:
      picker.xSelectedTime.formatTimeOfDay()
    else:
      "No time selected"

  method isAccessibilityElement(picker: TimePicker): bool =
    true

proc initTimePickerFields*(
    picker: TimePicker,
    selectedTime: TimeOfDay,
    hasSelectedTime = true,
    frame: Rect = AutoRect,
) =
  initViewFields(picker, frame)
  let fallback =
    if selectedTime.isValidTimeOfDay():
      selectedTime
    else:
      currentTimeOfDay()
  picker.xSelectedTime = fallback
  picker.xDraftTime = fallback
  picker.xHasSelectedTime = hasSelectedTime
  picker.xEditingPart = tppHour
  picker.xHasTrackingPart = false
  picker.xTrackingDone = false
  picker.acceptsFirstResponder = true
  picker.accessibilityRole = arGroup
  picker.accessibilityLabel = "Time picker"
  discard picker.withProtocol(TimePickerDrawing)
  discard picker.withProtocol(TimePickerPopupDrawing)
  discard picker.withProtocol(TimePickerPopupHitTesting)
  discard picker.withProtocol(TimePickerLayout)
  discard picker.withProtocol(TimePickerEvents)
  discard picker.withProtocol(TimePickerAccessibility)
  picker.applyInitialFrame(frame)

proc newTimePicker*(
    selectedTime: TimeOfDay, hasSelectedTime = true, frame: Rect = AutoRect
): TimePicker =
  result = TimePicker()
  result.initTimePickerFields(selectedTime, hasSelectedTime, frame)

proc newTimePicker*(frame: Rect = AutoRect): TimePicker =
  newTimePicker(currentTimeOfDay(), hasSelectedTime = false, frame = frame)

proc selectTime*(picker: TimePicker, time: TimeOfDay) {.discardable.} =
  if not time.isValidTimeOfDay():
    return
  picker.xHasTrackingPart = false
  picker.xTrackingDone = false
  picker.xSelectedTime = time
  picker.xDraftTime = time
  picker.xHasSelectedTime = true
  picker.needsDisplay = true
  picker.postAccessibilityNotification(anValueChanged)
  if not picker.xOnSelect.isNil:
    picker.xOnSelect(time)

proc confirmTime*(picker: TimePicker): bool =
  if not picker.xDraftTime.isValidTimeOfDay():
    return false
  picker.selectTime(picker.xDraftTime)
  true

proc confirmSelection*(picker: TimePicker): bool =
  picker.confirmTime()

proc commitTime*(picker: TimePicker): bool =
  picker.confirmTime()

proc titlePrefix*(button: TimePickerButton): string =
  button.xTitlePrefix

proc `titlePrefix=`*(button: TimePickerButton, value: string) =
  if button.xTitlePrefix == value:
    return
  button.xTitlePrefix = value
  button.updateTimeButtonTitle()

proc selectedTime*(button: TimePickerButton): TimeOfDay =
  button.xSelectedTime

proc `selectedTime=`*(button: TimePickerButton, time: TimeOfDay) =
  if not time.isValidTimeOfDay():
    return
  button.xSelectedTime = time
  button.xHasSelectedTime = true
  button.updateTimeButtonTitle()
  if not button.xTimePicker.isNil:
    button.xTimePicker.selectedTime = time
  button.postAccessibilityNotification(anValueChanged)

proc hasSelectedTime*(button: TimePickerButton): bool =
  button.xHasSelectedTime

proc `hasSelectedTime=`*(button: TimePickerButton, value: bool) =
  if value and not button.xSelectedTime.isValidTimeOfDay():
    button.xSelectedTime = currentTimeOfDay()
  if button.xHasSelectedTime == value:
    return
  button.xHasSelectedTime = value
  button.updateTimeButtonTitle()
  if not button.xTimePicker.isNil:
    button.xTimePicker.hasSelectedTime = value
  button.postAccessibilityNotification(anValueChanged)

proc onSelect*(button: TimePickerButton): TimePickerSelectionHandler =
  button.xOnSelect

proc `onSelect=`*(button: TimePickerButton, handler: TimePickerSelectionHandler) =
  button.xOnSelect = handler

proc timePicker*(button: TimePickerButton): TimePicker =
  button.xTimePicker

proc popupWindow*(button: TimePickerButton): Window =
  if not button.xPopupHost.isNil:
    return button.xPopupHost.popupWindow()

proc popupOpen*(button: TimePickerButton): bool =
  button.xPopupOpen

proc popupPresentation*(button: TimePickerButton): PopupPresentation =
  button.xPopupPresentation

proc effectivePopupPresentation*(button: TimePickerButton): PopupPresentation =
  let owner = button.ownerWindow()
  if owner.isNil:
    return ppInline
  owner.resolvedPopupPresentation(button.xPopupPresentation)

proc `popupPresentation=`*(button: TimePickerButton, value: PopupPresentation) =
  if button.xPopupPresentation == value:
    return
  let wasOpen = button.xPopupOpen
  if wasOpen:
    button.closePopup()
  button.xPopupPresentation = value
  if wasOpen:
    button.openPopup()

proc `popupOpen=`*(button: TimePickerButton, value: bool) =
  if value:
    button.openPopup()
  else:
    button.closePopup()

proc updateTimeButtonTitle(button: TimePickerButton) =
  button.title =
    if button.xHasSelectedTime:
      button.xTitlePrefix & " · " & button.xSelectedTime.formatTimeOfDay()
    else:
      button.xTitlePrefix & " · Any time"

proc ownerWindow(button: TimePickerButton): Window =
  let owner = button.window()
  if owner of Window:
    result = Window(owner)

proc clearPopupState(button: TimePickerButton, host: PopupHost = nil) =
  if not host.isNil and button.xPopupHost != host:
    return
  if not button.xTimePicker.isNil and not button.xTimePicker.superview().isNil:
    button.xTimePicker.removeFromSuperview()
  button.xPopupOpen = false
  button.xPopupHost = nil
  button.xTimePicker = nil
  button.setWidgetState(ssOpen, false)
  button.needsDisplay = true

proc dismissPopup(button: TimePickerButton, host: PopupHost, reason: DismissReason) =
  discard reason
  button.clearPopupState(host)

proc timePickerDidSelect(button: TimePickerButton, time: TimeOfDay) =
  button.selectedTime = time
  button.closePopup()
  if not button.xOnSelect.isNil:
    button.xOnSelect(time)
  discard button.sendAction()

proc openPopup*(button: TimePickerButton) =
  if button.xPopupOpen or not button.isEnabled():
    return
  let owner = button.ownerWindow()
  if owner.isNil:
    return
  let size = timePickerDefaultSize()
  let picker = newTimePicker(
    button.xSelectedTime,
    hasSelectedTime = button.xHasSelectedTime,
    frame = rect(0.0, 0.0, size.width, size.height),
  )
  picker.onSelect = proc(time: TimeOfDay) =
    button.timePickerDidSelect(time)

  button.xTimePicker = picker
  let host = newPopupHost(
    owner,
    button,
    picker,
    size,
    title = "Time Picker",
    presentation = button.xPopupPresentation,
    restoreResponder = Responder(button),
    onDismiss = proc(host: PopupHost, reason: DismissReason) =
      button.dismissPopup(host, reason),
  )
  button.xPopupHost = host
  if not host.presentPopup():
    button.clearPopupState(host)
    return

  button.xPopupOpen = true
  button.setWidgetState(ssOpen, true)
  button.needsDisplay = true

proc closePopup*(button: TimePickerButton) =
  let host = button.xPopupHost
  if not button.xPopupOpen and host.isNil:
    return
  if not host.isNil:
    discard host.dismissPopup()
  else:
    button.clearPopupState()

protocol TimePickerButtonEvents of ResponderEventProtocol:
  method mouseDown(button: TimePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      button.cancelActivationFeedback()
      button.setHighlighted(true)
      return true

  method mouseDragged(button: TimePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      button.setHighlighted(button.pointInside(event.location))
      return true

  method mouseUp(button: TimePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      let clicked = button.pointInside(event.location)
      button.setHighlighted(false)
      if clicked:
        button.popupOpen = not button.popupOpen()
      return true

  method keyDown(button: TimePickerButton, event: KeyEvent): bool =
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

protocol TimePickerButtonAccessibility of AccessibilityProtocol:
  method accessibilityRole(button: TimePickerButton): AccessibilityRole =
    arPopupButton

  method accessibilityLabel(button: TimePickerButton): string =
    if button.xAccessibilityLabel.len > 0:
      button.xAccessibilityLabel
    else:
      button.title()

  method accessibilityValue(button: TimePickerButton): string =
    if button.xHasSelectedTime:
      button.xSelectedTime.formatTimeOfDay()
    else:
      "No time selected"

  method accessibilityTraits(button: TimePickerButton): AccessibilityTraits =
    result = button.xAccessibilityTraits + {atButton}
    if not button.isEnabled():
      result.incl atDisabled
    if button.focused():
      result.incl atFocused

  method isAccessibilityElement(button: TimePickerButton): bool =
    true

  method accessibilityActionNames(button: TimePickerButton): seq[string] =
    @[AccessibilityActionShowMenu]

  method accessibilityPerformAction(button: TimePickerButton, action: string): bool =
    if action != AccessibilityActionShowMenu or not button.isEnabled():
      return false
    button.openPopup()
    true

proc initTimePickerButtonFields*(
    button: TimePickerButton,
    titlePrefix = "Time",
    selectedTime: TimeOfDay = TimeOfDay(),
    hasSelectedTime = false,
    frame: Rect = AutoRect,
) =
  initButtonFields(button, frame = frame)
  button.xTitlePrefix = titlePrefix
  button.xSelectedTime =
    if selectedTime.isValidTimeOfDay():
      selectedTime
    else:
      currentTimeOfDay()
  button.xHasSelectedTime = hasSelectedTime
  button.xPopupPresentation = ppAutomatic
  button.updateTimeButtonTitle()
  discard button.withProtocol(TimePickerButtonEvents)
  discard button.withProtocol(TimePickerButtonAccessibility)

proc newTimePickerButton*(
    titlePrefix = "Time", frame: Rect = AutoRect
): TimePickerButton =
  result = TimePickerButton()
  result.initTimePickerButtonFields(titlePrefix, frame = frame)

proc newTimePickerButton*(
    titlePrefix: string, selectedTime: TimeOfDay, frame: Rect = AutoRect
): TimePickerButton =
  result = TimePickerButton()
  result.initTimePickerButtonFields(
    titlePrefix, selectedTime, hasSelectedTime = true, frame = frame
  )

func isValidDateTime*(value: DateTime): bool =
  try:
    let date = initCalendarDate(value.year, value.month.ord, value.monthday)
    result =
      date.isValidCalendarDate() and value.hour in 0 .. 23 and value.minute in 0 .. 59 and
      value.second in 0 .. 59 and value.nanosecond in 0 .. 999_999_999
  except AssertionDefect:
    result = false

func isValidDateTimeValue*(value: DateTime): bool =
  value.isValidDateTime()

func calendarDate*(value: DateTime): CalendarDate =
  if value.isValidDateTime():
    result = initCalendarDate(value.year, value.month.ord, value.monthday)

func datePart*(value: DateTime): CalendarDate =
  value.calendarDate()

func timeOfDay*(value: DateTime): TimeOfDay =
  if value.isValidDateTime():
    result = initTimeOfDay(value.hour, value.minute, value.second, value.nanosecond)

func timePart*(value: DateTime): TimeOfDay =
  value.timeOfDay()

proc dateTimeWithParts(value: DateTime, date: CalendarDate, time: TimeOfDay): DateTime =
  if not date.isValidCalendarDate() or not time.isValidTimeOfDay():
    return
  dateTime(
    date.year,
    Month(date.month),
    date.day,
    time.hour,
    time.minute,
    time.second,
    time.nanosecond,
    value.timezone,
  )

proc initPickerDateTime*(
    year, month, day, hour, minute: int,
    second = 0,
    nanosecond = 0,
    zone: Timezone = local(),
): DateTime =
  let
    date = initCalendarDate(year, month, day)
    time = initTimeOfDay(hour, minute, second, nanosecond)
  if date.isValidCalendarDate() and time.isValidTimeOfDay():
    result = dateTime(year, Month(month), day, hour, minute, second, nanosecond, zone)

proc formatCalendarDateTime*(value: DateTime): string =
  if not value.isValidDateTime():
    return ""
  value.calendarDate().formatCalendarDate() & " · " &
    value.timeOfDay().formatTimeOfDay()

proc formatDateTimeValue*(value: DateTime): string =
  value.formatCalendarDateTime()

proc formatPickerDateTime*(value: DateTime): string =
  value.formatCalendarDateTime()

proc dateTimePickerDefaultSize*(): Size =
  initSize(DateTimePickerDefaultWidth, DateTimePickerDefaultHeight)

proc selectDateTime*(picker: DateTimePicker, value: DateTime) {.discardable.}
proc confirmDateTime*(picker: DateTimePicker): bool
proc openPopup*(button: DateTimePickerButton)
proc closePopup*(button: DateTimePickerButton)
proc updateDateTimeButtonTitle(button: DateTimePickerButton)
proc ownerWindow(button: DateTimePickerButton): Window

proc selectedDateTime*(picker: DateTimePicker): DateTime =
  picker.xSelectedDateTime

proc `selectedDateTime=`*(picker: DateTimePicker, value: DateTime) =
  if not value.isValidDateTime():
    return
  picker.xSelectedDateTime = value
  picker.xDraftDateTime = value
  picker.xHasSelectedDateTime = true
  if not picker.xDatePicker.isNil:
    picker.xDatePicker.selectedDate = value.calendarDate()
    picker.xDatePicker.hasSelectedDate = true
  if not picker.xTimePicker.isNil:
    picker.xTimePicker.selectedTime = value.timeOfDay()
    picker.xTimePicker.hasSelectedTime = true
  picker.needsDisplay = true

proc hasSelectedDateTime*(picker: DateTimePicker): bool =
  picker.xHasSelectedDateTime

proc `hasSelectedDateTime=`*(picker: DateTimePicker, value: bool) =
  if picker.xHasSelectedDateTime == value:
    return
  picker.xHasSelectedDateTime = value
  if not picker.xDatePicker.isNil:
    picker.xDatePicker.hasSelectedDate = value
  if not picker.xTimePicker.isNil:
    picker.xTimePicker.hasSelectedTime = value
  picker.needsDisplay = true

proc onSelect*(picker: DateTimePicker): DateTimePickerSelectionHandler =
  picker.xOnSelect

proc `onSelect=`*(picker: DateTimePicker, handler: DateTimePickerSelectionHandler) =
  picker.xOnSelect = handler

proc datePicker*(picker: DateTimePicker): DatePicker =
  picker.xDatePicker

proc timePicker*(picker: DateTimePicker): TimePicker =
  picker.xTimePicker

proc calendarDate*(picker: DateTimePicker): CalendarDate =
  picker.xSelectedDateTime.calendarDate()

proc timeOfDay*(picker: DateTimePicker): TimeOfDay =
  picker.xSelectedDateTime.timeOfDay()

proc updateDraftDate(picker: DateTimePicker, date: CalendarDate) =
  if not date.isValidCalendarDate():
    return
  picker.xDraftDateTime =
    picker.xDraftDateTime.dateTimeWithParts(date, picker.xDraftDateTime.timeOfDay())
  picker.needsDisplay = true

proc updateDraftTime(picker: DateTimePicker, time: TimeOfDay) =
  if not time.isValidTimeOfDay():
    return
  picker.xDraftDateTime =
    picker.xDraftDateTime.dateTimeWithParts(picker.xDraftDateTime.calendarDate(), time)
  picker.needsDisplay = true

proc dateTimePickerDateDidChange(picker: DateTimePicker, date: CalendarDate) =
  picker.updateDraftDate(date)

proc dateTimePickerTimeDidConfirm(picker: DateTimePicker, time: TimeOfDay) =
  picker.updateDraftTime(time)
  discard picker.confirmDateTime()

protocol DateTimePickerLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(picker: DateTimePicker): IntrinsicSize =
    initIntrinsicSize(dateTimePickerDefaultSize())

  method layoutSubviews(picker: DateTimePicker) =
    let bounds = picker.bounds()
    picker.xDatePicker.frame =
      rect(0.0, 0.0, bounds.size.width, DatePickerDefaultHeight)
    picker.xTimePicker.frame = rect(
      0.0,
      DatePickerDefaultHeight,
      bounds.size.width,
      max(bounds.size.height - DatePickerDefaultHeight, TimePickerDefaultHeight),
    )

protocol DateTimePickerPopupDrawing of ViewDrawingProtocol:
  method drawLevel(picker: DateTimePicker): ZLevel =
    PopupDrawLevel

protocol DateTimePickerPopupHitTesting of ViewProtocol:
  method hitTestLevel(picker: DateTimePicker, point: Point): int =
    discard point
    PopupDrawLevel.int

protocol DateTimePickerEvents of ResponderEventProtocol:
  method keyDown(picker: DateTimePicker, event: KeyEvent): bool =
    case event.key
    of keyEnter, keySpace:
      picker.confirmDateTime()
    of keyArrowLeft, keyArrowRight:
      picker.xDatePicker.keyDown(event)
    of keyArrowUp, keyArrowDown:
      picker.xTimePicker.keyDown(event)
    else:
      false

protocol DateTimePickerAccessibility of AccessibilityProtocol:
  method accessibilityRole(picker: DateTimePicker): AccessibilityRole =
    arGroup

  method accessibilityLabel(picker: DateTimePicker): string =
    if picker.xAccessibilityLabel.len > 0:
      picker.xAccessibilityLabel
    else:
      "Date and time picker"

  method accessibilityValue(picker: DateTimePicker): string =
    if picker.xHasSelectedDateTime:
      picker.xSelectedDateTime.formatCalendarDateTime()
    else:
      "No date and time selected"

  method isAccessibilityElement(picker: DateTimePicker): bool =
    true

proc initDateTimePickerFields*(
    picker: DateTimePicker,
    selectedDateTime: DateTime,
    hasSelectedDateTime = true,
    frame: Rect = AutoRect,
) =
  initViewFields(picker, frame)
  let fallback =
    if selectedDateTime.isValidDateTime():
      selectedDateTime
    else:
      now()
  picker.xSelectedDateTime = fallback
  picker.xDraftDateTime = fallback
  picker.xHasSelectedDateTime = hasSelectedDateTime
  picker.xDatePicker = newDatePicker(
    fallback.calendarDate(),
    hasSelectedDate = hasSelectedDateTime,
    frame = rect(0.0, 0.0, DateTimePickerDefaultWidth, DatePickerDefaultHeight),
  )
  picker.xTimePicker = newTimePicker(
    fallback.timeOfDay(),
    hasSelectedTime = hasSelectedDateTime,
    frame = rect(
      0.0, DatePickerDefaultHeight, DateTimePickerDefaultWidth, TimePickerDefaultHeight
    ),
  )
  picker.addSubview(picker.xDatePicker)
  picker.addSubview(picker.xTimePicker)
  let pickerRef = picker.unsafeWeakRef()
  picker.xDatePicker.onSelect = proc(date: CalendarDate) =
    if not pickerRef.isNil:
      pickerRef[].dateTimePickerDateDidChange(date)
  picker.xTimePicker.onSelect = proc(time: TimeOfDay) =
    if not pickerRef.isNil:
      pickerRef[].dateTimePickerTimeDidConfirm(time)
  picker.acceptsFirstResponder = true
  picker.accessibilityRole = arGroup
  picker.accessibilityLabel = "Date and time picker"
  discard picker.withProtocol(DateTimePickerLayout)
  discard picker.withProtocol(DateTimePickerPopupDrawing)
  discard picker.withProtocol(DateTimePickerPopupHitTesting)
  discard picker.withProtocol(DateTimePickerEvents)
  discard picker.withProtocol(DateTimePickerAccessibility)
  picker.applyInitialFrame(frame)

proc newDateTimePicker*(
    selectedDateTime: DateTime, hasSelectedDateTime = true, frame: Rect = AutoRect
): DateTimePicker =
  result = DateTimePicker()
  result.initDateTimePickerFields(selectedDateTime, hasSelectedDateTime, frame)

proc newDateTimePicker*(frame: Rect = AutoRect): DateTimePicker =
  newDateTimePicker(now(), hasSelectedDateTime = false, frame = frame)

proc selectDateTime*(picker: DateTimePicker, value: DateTime) {.discardable.} =
  if not value.isValidDateTime():
    return
  picker.xSelectedDateTime = value
  picker.xDraftDateTime = value
  picker.xHasSelectedDateTime = true
  if not picker.xDatePicker.isNil:
    picker.xDatePicker.selectedDate = value.calendarDate()
    picker.xDatePicker.hasSelectedDate = true
  if not picker.xTimePicker.isNil:
    picker.xTimePicker.selectedTime = value.timeOfDay()
    picker.xTimePicker.hasSelectedTime = true
  picker.needsDisplay = true
  picker.postAccessibilityNotification(anValueChanged)
  if not picker.xOnSelect.isNil:
    picker.xOnSelect(value)

proc confirmDateTime*(picker: DateTimePicker): bool =
  if not picker.xTimePicker.isNil:
    picker.updateDraftTime(picker.xTimePicker.xDraftTime)
  if not picker.xDraftDateTime.isValidDateTime():
    return false
  picker.selectDateTime(picker.xDraftDateTime)
  true

proc confirmSelection*(picker: DateTimePicker): bool =
  picker.confirmDateTime()

proc commitDateTime*(picker: DateTimePicker): bool =
  picker.confirmDateTime()

proc titlePrefix*(button: DateTimePickerButton): string =
  button.xTitlePrefix

proc `titlePrefix=`*(button: DateTimePickerButton, value: string) =
  if button.xTitlePrefix == value:
    return
  button.xTitlePrefix = value
  button.updateDateTimeButtonTitle()

proc selectedDateTime*(button: DateTimePickerButton): DateTime =
  button.xSelectedDateTime

proc `selectedDateTime=`*(button: DateTimePickerButton, value: DateTime) =
  if not value.isValidDateTime():
    return
  button.xSelectedDateTime = value
  button.xHasSelectedDateTime = true
  button.updateDateTimeButtonTitle()
  if not button.xDateTimePicker.isNil:
    button.xDateTimePicker.selectedDateTime = value
  button.postAccessibilityNotification(anValueChanged)

proc hasSelectedDateTime*(button: DateTimePickerButton): bool =
  button.xHasSelectedDateTime

proc `hasSelectedDateTime=`*(button: DateTimePickerButton, value: bool) =
  if value and not button.xSelectedDateTime.isValidDateTime():
    button.xSelectedDateTime = now()
  if button.xHasSelectedDateTime == value:
    return
  button.xHasSelectedDateTime = value
  button.updateDateTimeButtonTitle()
  if not button.xDateTimePicker.isNil:
    button.xDateTimePicker.hasSelectedDateTime = value
  button.postAccessibilityNotification(anValueChanged)

proc onSelect*(button: DateTimePickerButton): DateTimePickerSelectionHandler =
  button.xOnSelect

proc `onSelect=`*(
    button: DateTimePickerButton, handler: DateTimePickerSelectionHandler
) =
  button.xOnSelect = handler

proc dateTimePicker*(button: DateTimePickerButton): DateTimePicker =
  button.xDateTimePicker

proc popupWindow*(button: DateTimePickerButton): Window =
  if not button.xPopupHost.isNil:
    return button.xPopupHost.popupWindow()

proc popupOpen*(button: DateTimePickerButton): bool =
  button.xPopupOpen

proc popupPresentation*(button: DateTimePickerButton): PopupPresentation =
  button.xPopupPresentation

proc effectivePopupPresentation*(button: DateTimePickerButton): PopupPresentation =
  let owner = button.ownerWindow()
  if owner.isNil:
    return ppInline
  owner.resolvedPopupPresentation(button.xPopupPresentation)

proc `popupPresentation=`*(button: DateTimePickerButton, value: PopupPresentation) =
  if button.xPopupPresentation == value:
    return
  let wasOpen = button.xPopupOpen
  if wasOpen:
    button.closePopup()
  button.xPopupPresentation = value
  if wasOpen:
    button.openPopup()

proc `popupOpen=`*(button: DateTimePickerButton, value: bool) =
  if value:
    button.openPopup()
  else:
    button.closePopup()

proc updateDateTimeButtonTitle(button: DateTimePickerButton) =
  button.title =
    if button.xHasSelectedDateTime:
      button.xTitlePrefix & " · " & button.xSelectedDateTime.formatCalendarDateTime()
    else:
      button.xTitlePrefix & " · Any date and time"

proc ownerWindow(button: DateTimePickerButton): Window =
  let owner = button.window()
  if owner of Window:
    result = Window(owner)

proc clearPopupState(button: DateTimePickerButton, host: PopupHost = nil) =
  if not host.isNil and button.xPopupHost != host:
    return
  if not button.xDateTimePicker.isNil and not button.xDateTimePicker.superview().isNil:
    button.xDateTimePicker.removeFromSuperview()
  button.xPopupOpen = false
  button.xPopupHost = nil
  button.xDateTimePicker = nil
  button.setWidgetState(ssOpen, false)
  button.needsDisplay = true

proc dismissPopup(
    button: DateTimePickerButton, host: PopupHost, reason: DismissReason
) =
  discard reason
  button.clearPopupState(host)

proc dateTimePickerDidSelect(button: DateTimePickerButton, value: DateTime) =
  button.selectedDateTime = value
  button.closePopup()
  if not button.xOnSelect.isNil:
    button.xOnSelect(value)
  discard button.sendAction()

proc openPopup*(button: DateTimePickerButton) =
  if button.xPopupOpen or not button.isEnabled():
    return
  let owner = button.ownerWindow()
  if owner.isNil:
    return
  let size = dateTimePickerDefaultSize()
  let picker = newDateTimePicker(
    button.xSelectedDateTime,
    hasSelectedDateTime = button.xHasSelectedDateTime,
    frame = rect(0.0, 0.0, size.width, size.height),
  )
  picker.onSelect = proc(value: DateTime) =
    button.dateTimePickerDidSelect(value)

  button.xDateTimePicker = picker
  let host = newPopupHost(
    owner,
    button,
    picker,
    size,
    title = "Date and Time Picker",
    presentation = button.xPopupPresentation,
    restoreResponder = Responder(button),
    onDismiss = proc(host: PopupHost, reason: DismissReason) =
      button.dismissPopup(host, reason),
  )
  button.xPopupHost = host
  if not host.presentPopup():
    button.clearPopupState(host)
    return

  button.xPopupOpen = true
  button.setWidgetState(ssOpen, true)
  button.needsDisplay = true

proc closePopup*(button: DateTimePickerButton) =
  let host = button.xPopupHost
  if not button.xPopupOpen and host.isNil:
    return
  if not host.isNil:
    discard host.dismissPopup()
  else:
    button.clearPopupState()

protocol DateTimePickerButtonEvents of ResponderEventProtocol:
  method mouseDown(button: DateTimePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      button.cancelActivationFeedback()
      button.setHighlighted(true)
      return true

  method mouseDragged(button: DateTimePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      button.setHighlighted(button.pointInside(event.location))
      return true

  method mouseUp(button: DateTimePickerButton, event: MouseEvent): bool =
    if button.isEnabled() and event.button == mbPrimary:
      let clicked = button.pointInside(event.location)
      button.setHighlighted(false)
      if clicked:
        button.popupOpen = not button.popupOpen()
      return true

  method keyDown(button: DateTimePickerButton, event: KeyEvent): bool =
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

protocol DateTimePickerButtonAccessibility of AccessibilityProtocol:
  method accessibilityRole(button: DateTimePickerButton): AccessibilityRole =
    arPopupButton

  method accessibilityLabel(button: DateTimePickerButton): string =
    if button.xAccessibilityLabel.len > 0:
      button.xAccessibilityLabel
    else:
      button.title()

  method accessibilityValue(button: DateTimePickerButton): string =
    if button.xHasSelectedDateTime:
      button.xSelectedDateTime.formatCalendarDateTime()
    else:
      "No date and time selected"

  method accessibilityTraits(button: DateTimePickerButton): AccessibilityTraits =
    result = button.xAccessibilityTraits + {atButton}
    if not button.isEnabled():
      result.incl atDisabled
    if button.focused():
      result.incl atFocused

  method isAccessibilityElement(button: DateTimePickerButton): bool =
    true

  method accessibilityActionNames(button: DateTimePickerButton): seq[string] =
    @[AccessibilityActionShowMenu]

  method accessibilityPerformAction(
      button: DateTimePickerButton, action: string
  ): bool =
    if action != AccessibilityActionShowMenu or not button.isEnabled():
      return false
    button.openPopup()
    true

proc initDateTimePickerButtonFields*(
    button: DateTimePickerButton,
    titlePrefix = "Date & Time",
    selectedDateTime: DateTime = DateTime(),
    hasSelectedDateTime = false,
    frame: Rect = AutoRect,
) =
  initButtonFields(button, frame = frame)
  button.xTitlePrefix = titlePrefix
  button.xSelectedDateTime =
    if selectedDateTime.isValidDateTime():
      selectedDateTime
    else:
      now()
  button.xHasSelectedDateTime = hasSelectedDateTime
  button.xPopupPresentation = ppAutomatic
  button.updateDateTimeButtonTitle()
  discard button.withProtocol(DateTimePickerButtonEvents)
  discard button.withProtocol(DateTimePickerButtonAccessibility)

proc newDateTimePickerButton*(
    titlePrefix = "Date & Time", frame: Rect = AutoRect
): DateTimePickerButton =
  result = DateTimePickerButton()
  result.initDateTimePickerButtonFields(titlePrefix, frame = frame)

proc newDateTimePickerButton*(
    titlePrefix: string, selectedDateTime: DateTime, frame: Rect = AutoRect
): DateTimePickerButton =
  result = DateTimePickerButton()
  result.initDateTimePickerButtonFields(
    titlePrefix, selectedDateTime, hasSelectedDateTime = true, frame = frame
  )
