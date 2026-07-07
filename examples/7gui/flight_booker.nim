import std/[options, strutils]

import merenda/nimkit

import sigils/[core, selectors]

let
  TextColor = color(0.08, 0.09, 0.11, 1.0)
  ErrorColor = color(0.82, 0.08, 0.08, 1.0)

type DateKey = object
  year: int
  month: int
  day: int

let
  app = sharedApplication()
  window = newWindow("7GUIs Flight Booker", frame = rect(140, 140, 430, 260))
  root = newView()
  layout = newStackView(laVertical)
  form = newFormView()
  title = newTitleLabel("Flight Booker")
  tripKind = newComboBox(["one-way flight", "return flight"])
  startDate = newTextField("04.04.2014")
  returnDate = newTextField("04.04.2014")
  bookButton = newButton("Book")
  status = newStatusLabel("")
  changedAction = actionSelector("sevenGuiFlightBookerChanged")
  bookAction = actionSelector("sevenGuiFlightBookerBook")

func leapYear(year: int): bool =
  (year mod 4 == 0 and year mod 100 != 0) or year mod 400 == 0

func daysInMonth(year, month: int): int =
  case month
  of 1, 3, 5, 7, 8, 10, 12:
    31
  of 4, 6, 9, 11:
    30
  of 2:
    if year.leapYear(): 29 else: 28
  else:
    0

func `<`(left, right: DateKey): bool =
  if left.year != right.year:
    return left.year < right.year
  if left.month != right.month:
    return left.month < right.month
  left.day < right.day

proc parseDateKey(text: string): Option[DateKey] =
  let parts = text.strip().split(".")
  if parts.len != 3:
    return none(DateKey)
  try:
    let
      day = parts[0].parseInt()
      month = parts[1].parseInt()
      year = parts[2].parseInt()
    if month notin 1 .. 12:
      return none(DateKey)
    if day notin 1 .. daysInMonth(year, month):
      return none(DateKey)
    some(DateKey(year: year, month: month, day: day))
  except ValueError:
    none(DateKey)

proc updateBookingState() =
  let
    oneWay = tripKind.selectedIndex == 0
    start = startDate.stringValue.parseDateKey()
    finish = returnDate.stringValue.parseDateKey()
    validReturnOrder =
      oneWay or (start.isSome and finish.isSome and not (finish.get() < start.get()))

  returnDate.enabled = not oneWay
  startDate.textColor = if start.isSome: TextColor else: ErrorColor
  returnDate.textColor = if oneWay or finish.isSome: TextColor else: ErrorColor
  bookButton.enabled = start.isSome and (oneWay or finish.isSome) and validReturnOrder

  if not bookButton.enabled:
    status.text = "Enter valid dates as dd.mm.yyyy."

proc onInputChanged(textField: TextField, sender: DynamicAgent) {.slot.} =
  discard textField
  if sender == DynamicAgent(startDate) or sender == DynamicAgent(returnDate):
    updateBookingState()

proc onTripKindChanged(sender: DynamicAgent) =
  discard sender
  updateBookingState()

proc bookFlight(sender: DynamicAgent) =
  discard sender
  if tripKind.selectedIndex == 0:
    status.text = "You have booked a one-way flight on " & startDate.stringValue & "."
  else:
    status.text =
      "You have booked a return flight from " & startDate.stringValue & " to " &
      returnDate.stringValue & "."

tripKind.selectedIndex = 0
tripKind.target = newActionTarget(changedAction, onTripKindChanged)
tripKind.action = changedAction
bookButton.target = newActionTarget(bookAction, bookFlight)
bookButton.action = bookAction
startDate.connect(textDidChange, startDate, onInputChanged)
returnDate.connect(textDidChange, returnDate, onInputChanged)

form.edgeInsets = insets(0.0)
form.spacing[dcol] = 12.0
form.spacing[drow] = 10.0
form.minFieldWidth = 190.0
form.addRow(newFormLabel("Trip"), tripKind)
form.addRow(newFormLabel("Start date"), startDate)
form.addRow(newFormLabel("Return date"), returnDate)

layout.spacing = 14.0
layout.alignment = svaFill
layout.addArrangedSubview(title, form, bookButton, status)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

updateBookingState()
app.runWindow(window, root, startDate)
