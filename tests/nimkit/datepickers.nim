import std/[times, unittest]

import figdraw

import merenda/nimkit

suite "NimKit date pickers":
  test "calendar dates provide validation, ordering, and formatting":
    let
      leapDay = initCalendarDate(2024, 2, 29)
      ordinaryFebruary = initCalendarDate(2025, 2, 28)
      invalid = initCalendarDate(2025, 2, 29)

    check leapDay.isValidCalendarDate()
    check leapDay.daysInMonth() == 29
    check ordinaryFebruary.isValidCalendarDate()
    check ordinaryFebruary.daysInMonth() == 28
    check not invalid.isValidCalendarDate()
    check initCalendarDate(2025, 7, 1).weekday() == 2
    check initCalendarDate(2025, 7, 1).formatCalendarDate() == "Jul 01, 2025"
    check initCalendarDate(2025, 7, 1).formatCalendarMonth() == "July 2025"
    check initCalendarDate(2025, 6, 30) < initCalendarDate(2025, 7, 1)
    check initCalendarDate(2025, 7, 1) <= initCalendarDate(2025, 7, 1)
    check initCalendarDate(2025, 13, 1).daysInMonth() == 0

  test "clock times provide validation, ordering, and formatting":
    let
      early = initTimeOfDay(9, 5, 2)
      late = initClockTime(17, 45, 8)
      invalid = initTimeOfDay(24, 0)

    check early.isValidTimeOfDay()
    check late.isValidClockTime()
    check not invalid.isValidTimeValue()
    check early < late
    check early <= early
    check early.formatTimeOfDay() == "09:05:02"
    check late.formatClockTime() == "17:45:08"
    check initCalendarTime(0, 0).formatTimeValue() == "00:00:00"

  test "time picker selection updates state and invokes its callback":
    let
      initial = initTimeOfDay(9, 30, 15)
      next = initTimeOfDay(17, 45, 8)
      picker = newTimePicker(initial)
    var
      selectedCount = 0
      callbackTime: TimeOfDay
    picker.onSelect = proc(time: TimeOfDay) =
      inc selectedCount
      callbackTime = time

    check picker.selectedTime == initial
    check picker.hasSelectedTime
    check picker.sizeThatFits() == timePickerDefaultSize()
    picker.selectTime(next)
    check selectedCount == 1
    check callbackTime == next
    check picker.selectedTime == next
    check picker.accessibilityValue() == "17:45:08"

    picker.hasSelectedTime = false
    check not picker.hasSelectedTime
    check picker.accessibilityValue() == "No time selected"

  test "time picker button edits and forwards a selected time":
    let
      selected = initTimeOfDay(9, 30, 15)
      root = newView(frame = rect(0, 0, 400, 300))
      window = newWindow("Time Picker", frame = rect(0, 0, 400, 300))
      button = newTimePickerButton("At", selected, rect(10, 10, 140, 32))
    var
      selectedCount = 0
      callbackTime: TimeOfDay
    button.onSelect = proc(time: TimeOfDay) =
      inc selectedCount
      callbackTime = time
    root.addSubview(button)
    window.setContentView(root)
    button.popupPresentation = ppInline

    check button.title == "At · 09:30:15"
    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseUpAt(initPoint(20, 20))
    check button.popupOpen()
    let picker = button.timePicker()
    check not picker.isNil
    check picker.superview() == root
    check window.hasActiveTransientSession()

    # The minute down control changes 30 to 29 before Done commits the edit.
    let minuteDown = picker.pointToWindow(initPoint(117, 94))
    check window.mouseDownAt(minuteDown)
    check window.mouseUpAt(minuteDown)
    let done = picker.pointToWindow(initPoint(210, 150))
    check window.mouseDownAt(done)
    check window.mouseUpAt(done)
    check selectedCount == 1
    check callbackTime == initTimeOfDay(9, 29, 15)
    check button.selectedTime == callbackTime
    check button.title == "At · 09:29:15"
    check not button.popupOpen()
    check button.timePicker().isNil
    check not window.hasActiveTransientSession()

  test "date-time picker combines calendar and clock selections":
    let
      initial = dateTime(2025, mJul, 24, 9, 30, 15, zone = utc())
      nextDate = initCalendarDate(2025, 8, 3)
      nextTime = initTimeOfDay(17, 45, 8)
      picker = newDateTimePicker(initial)
    var
      selectedCount = 0
      callbackDateTime: DateTime
    picker.onSelect = proc(value: DateTime) =
      inc selectedCount
      callbackDateTime = value

    check picker.selectedDateTime == initial
    check picker.hasSelectedDateTime
    check picker.calendarDate() == initCalendarDate(2025, 7, 24)
    check picker.timePicker().selectedTime == initTimeOfDay(9, 30, 15)
    check picker.sizeThatFits() == dateTimePickerDefaultSize()
    picker.datePicker().selectDate(nextDate)
    check picker.confirmDateTime()
    check selectedCount == 1
    check callbackDateTime == dateTime(2025, mAug, 3, 9, 30, 15, zone = utc())
    picker.timePicker().selectTime(nextTime)
    check selectedCount == 2
    check picker.selectedDateTime == dateTime(2025, mAug, 3, 17, 45, 8, zone = utc())

    picker.hasSelectedDateTime = false
    check not picker.hasSelectedDateTime
    check picker.accessibilityValue() == "No date and time selected"

  test "date-time confirmation commits a pending child time edit":
    let
      initial = dateTime(2025, mJul, 24, 9, 30, 15, zone = utc())
      picker = newDateTimePicker(initial)

    check picker.timePicker().keyDown(
      KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord)
    )
    check picker.confirmDateTime()
    check picker.selectedDateTime == dateTime(2025, mJul, 24, 10, 30, 15, zone = utc())

  test "date-time picker button commits the combined inline selection":
    let
      selected = dateTime(2025, mJul, 24, 9, 30, 15, zone = utc())
      root = newView(frame = rect(0, 0, 500, 620))
      window = newWindow("Date and Time Picker", frame = rect(0, 0, 500, 620))
      button = newDateTimePickerButton("Updated", selected, rect(10, 10, 180, 32))
    var
      selectedCount = 0
      callbackDateTime: DateTime
    button.onSelect = proc(value: DateTime) =
      inc selectedCount
      callbackDateTime = value
    root.addSubview(button)
    window.setContentView(root)
    button.popupPresentation = ppInline

    check button.title == "Updated · Jul 24, 2025 · 09:30:15"
    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseUpAt(initPoint(20, 20))
    check button.popupOpen()
    let picker = button.dateTimePicker()
    check not picker.isNil
    check picker.superview() == root
    check window.hasActiveTransientSession()

    # July 23 is in the fourth calendar row and Wednesday column.
    let datePoint = picker.datePicker().pointToWindow(initPoint(125.5, 166.0))
    check window.mouseDownAt(datePoint)
    check window.mouseUpAt(datePoint)
    let minuteDown = picker.timePicker().pointToWindow(initPoint(117, 94))
    check window.mouseDownAt(minuteDown)
    check window.mouseUpAt(minuteDown)
    let done = picker.timePicker().pointToWindow(initPoint(210, 150))
    check window.mouseDownAt(done)
    check window.mouseUpAt(done)
    check selectedCount == 1
    check callbackDateTime == dateTime(2025, mJul, 23, 9, 29, 15, zone = utc())
    check button.selectedDateTime == callbackDateTime
    check button.title == "Updated · Jul 23, 2025 · 09:29:15"
    check not button.popupOpen()
    check button.dateTimePicker().isNil
    check not window.hasActiveTransientSession()

  test "date picker selection updates state and invokes its callback":
    let
      initial = initCalendarDate(2025, 7, 24)
      next = initCalendarDate(2025, 8, 3)
      picker = newDatePicker(initial)
    var
      selectedCount = 0
      callbackDate: CalendarDate
    picker.onSelect = proc(date: CalendarDate) =
      inc selectedCount
      callbackDate = date

    check picker.selectedDate == initial
    check picker.displayedMonth == initCalendarDate(2025, 7, 1)
    check picker.hasSelectedDate
    check picker.sizeThatFits() == datePickerDefaultSize()
    picker.selectDate(next)
    check selectedCount == 1
    check callbackDate == next
    check picker.selectedDate == next
    check picker.displayedMonth == initCalendarDate(2025, 8, 1)
    check picker.accessibilityValue() == "Aug 03, 2025"

    picker.hasSelectedDate = false
    check not picker.hasSelectedDate
    check picker.accessibilityValue() == "No date selected"

  test "date picker uses themed light and dark calendar colors":
    let
      picker =
        newDatePicker(initCalendarDate(2025, 7, 24), frame = rect(0, 0, 252, 244))
      darkAppearance = initAppearance(initDarkBSDTheme())
      darkStyle = darkAppearance.resolveBoxStyle(controlStyle(srDatePicker))
      darkSelectedStyle =
        darkAppearance.resolveBoxStyle(controlStyle(srDatePicker, {ssSelected}))
      lightAppearance = initAppearance(initMacOSTheme())
      lightStyle = lightAppearance.resolveBoxStyle(controlStyle(srDatePicker))
      renders = buildRenders(picker, darkAppearance)

    check darkStyle.box.fill ==
      darkAppearance.fillToken("comboBox.item.fill", fill(color(1.0, 1.0, 1.0, 1.0)))
    check darkStyle.text.color ==
      darkAppearance.colorToken("comboBox.item.text.color", color(0.0, 0.0, 0.0, 1.0))
    check darkStyle.box.fill.centerColor().r < 0.5'f32
    check darkStyle.text.color.r > 0.5'f32
    check darkSelectedStyle.box.fill ==
      darkAppearance.fillToken("accent", fill(color(0.0, 0.0, 0.0, 1.0)))
    check lightStyle.box.fill.centerColor().r > darkStyle.box.fill.centerColor().r
    check PopupDrawLevel in renders.layers

    var hasThemedCalendarSurface = false
    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == darkStyle.box.fill:
        hasThemedCalendarSurface = true
    check hasThemedCalendarSurface

  test "date picker button opens an inline picker and forwards selection":
    let
      selected = initCalendarDate(2025, 7, 24)
      root = newView(frame = rect(0, 0, 400, 360))
      window = newWindow("Date Picker", frame = rect(0, 0, 400, 360))
      button = newDatePickerButton("From", selected, rect(10, 10, 140, 32))
      action = actionSelector("testDatePickerAction")
    var
      selectedCount = 0
      callbackDate: CalendarDate
      actionCount = 0
    button.onSelect = proc(date: CalendarDate) =
      inc selectedCount
      callbackDate = date
    button.target = newActionTarget(
      action,
      proc(sender: DynamicAgent) =
        check sender == DynamicAgent(button)
        inc actionCount
      ,
    )
    button.action = action
    root.addSubview(button)
    window.setContentView(root)
    button.popupPresentation = ppInline

    check button.title == "From · Jul 24, 2025"
    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseUpAt(initPoint(20, 20))
    check button.popupOpen()
    let picker = button.datePicker()
    check not picker.isNil
    check picker.superview() == root
    check window.hasActiveTransientSession()

    # July 23 is in the fourth calendar row and Wednesday column.
    let datePoint = picker.pointToWindow(initPoint(125.5, 166.0))
    check window.mouseDownAt(datePoint)
    check window.mouseUpAt(datePoint)
    check selectedCount == 1
    check callbackDate == initCalendarDate(2025, 7, 23)
    check actionCount == 1
    check button.selectedDate == callbackDate
    check button.title == "From · Jul 23, 2025"
    check not button.popupOpen()
    check button.datePicker().isNil
    check not window.hasActiveTransientSession()
