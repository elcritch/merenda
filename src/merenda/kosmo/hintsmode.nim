## Kitty-style hint mode: pick visible text with labeled keyboard markers.
##
## A surface collects `KosmoHint` values for the text it currently shows,
## `presentKosmoHints` overlays markers with prefix-free labels, and typing a
## marker's label activates the hint. Collectors only read rendered state and
## the overlay is a transient sibling view, so hint sessions leave editor
## state such as Moe registers, language-server hover requests, and completion
## popups untouched.

import std/[options, strutils, unicode]

import ../nimkit as nimkit except performKeyEquivalent
from ../nimkit/foundation/selectors import performKeyEquivalent, interceptKeyEquivalent
import ../nimkit/text/[searchmatching, textbytecursors]

type
  KosmoHintKind* = enum
    khkLink ## URLs such as ``https://example.com/``.
    khkPath ## Local file locations, with optional ``:line`` or ``(line)``.
    khkWord ## Words like double-click selections.
    khkHash ## Lowercase hexadecimal hashes such as Git revisions.

  KosmoHintAction* = enum
    khaOpen ## Open links in the browser and paths in the editor.
    khaCopy ## Copy the matched text to the clipboard.
    khaInsert ## Type the matched text into the focused terminal.

  KosmoHintSpan* = object ## A post-processed match as half-open UTF-8 byte offsets.
    first*, last*: int

  KosmoHintText* = object ## One matched snippet of the searched text.
    text*: string
    span*: KosmoHintSpan
    fileLocation*: Option[nimkit.TerminalFileLocation]
      ## Resolved file location; present for path hints only.

  KosmoHint* = object ## A matched snippet with its marker label and screen position.
    text*: string
    label*: string
    matchRect*: nimkit.Rect ## The extent of the match, in host coordinates.
    markerRect*: nimkit.Rect ## The match's first cell, in host coordinates.
    fileLocation*: Option[nimkit.TerminalFileLocation]

  KosmoHintActivation* = object ## Host-supplied follow-up actions for a selected hint.
    openLink*: proc(url: string): bool {.closure.}
    openFile*: proc(location: nimkit.TerminalFileLocation): bool {.closure.}
    insertText*: proc(text: string): bool {.closure.}

  KosmoHintOverlay* = ref object of nimkit.View
    xHints: seq[KosmoHint]
    xTyped: string
    xDismissed: bool
    xOnActivate: proc(hint: KosmoHint) {.closure.}
    xRestoreFirstResponder: nimkit.Responder
    xHostBoundsSize: nimkit.Size

const
  KosmoHintAlphabet* = "0123456789abcdefghijklmnopqrstuvwxyz"
    ## Marker characters, in Kitty's digits-then-letters order.
  KosmoHintMinimumRunes* = 3
  KosmoHintWordCharacters* =
    {':', '@', '-', '.', '/', '_', '~', '?', '&', '=', '%', '+', '#'}
    ## Extra characters treated as word parts, like Kitty's word selection.
    ## The colon keeps URLs such as ``https://example.com`` in one word.

proc hintLinkPattern(): nimkit.TextSearchPattern =
  nimkit.initTextSearchPattern(
    r"""(?i)\b(?:https?|file|ftp|irc|gemini|gopher|news)://[^\s<>"'`\[\]{}|\\^\x00-\x1f]{3,}""",
    regularExpression = true,
    caseSensitive = false,
  )

proc hintPathPattern(): nimkit.TextSearchPattern =
  nimkit.initTextSearchPattern(
    r"""[^\s]*/[^\s]+|[^\s]+\.[a-zA-Z0-9]{1,7}(?![a-zA-Z0-9.])""",
    regularExpression = true,
    caseSensitive = true,
  )

proc hintHashPattern(): nimkit.TextSearchPattern =
  nimkit.initTextSearchPattern(
    r"\b[0-9a-f]{7,64}\b", regularExpression = true, caseSensitive = true
  )

func closingHintCharacter(open: char): char =
  case open
  of '(': ')'
  of '[': ']'
  of '{': '}'
  of '<': '>'
  of '"', '\'', '`': open
  else: '\0'

proc truncateHintAtCloser(text: string, span: var KosmoHintSpan) =
  ## Stop a URL at the closer matching an opener right before the match.
  if span.first == 0 or span.last <= span.first:
    return
  let closer = closingHintCharacter(text[span.first - 1])
  if closer == '\0':
    return
  let closing = text.find(closer, span.first)
  if closing > span.first and closing < span.last:
    span.last = closing

proc trimHintEnclosure(text: string, span: var KosmoHintSpan) =
  ## Remove brackets or quotes enclosing a path candidate, like Kitty.
  if span.last <= span.first + 1 or span.first >= text.len:
    return
  let closer = closingHintCharacter(text[span.first])
  if closer == '\0':
    return
  if text[span.last - 1] == closer:
    inc span.first
    dec span.last
  elif span.last < text.len and text[span.last] == closer:
    inc span.first

proc trimHintTail(text: string, span: var KosmoHintSpan) =
  ## Drop trailing sentence punctuation and closing brackets whose opener is
  ## not part of the match, so snippets like ``(see url)`` and ``path.nim,``
  ## do not keep the tail. Balanced pairs such as ``wiki/Foo_(bar)`` survive.
  while span.last > span.first:
    let last = text[span.last - 1]
    if last in {'.', ',', ';', ':', '!', '?'}:
      dec span.last
      continue
    if last in {')', ']', '}', '>', '"', '\''}:
      let opener =
        case last
        of ')': '('
        of ']': '['
        of '}': '{'
        of '>': '<'
        else: last
      if text.find(opener, span.first, span.last - 2) >= 0:
        break
      dec span.last
      continue
    break

proc parseHintParenthesis(text: string, start: int): int =
  ## Return the index just past a ``digits[, digits]`` group in parentheses.
  if start >= text.len or text[start] != '(':
    return -1
  var index = start + 1
  while index < text.len and text[index] == ' ':
    inc index
  if index >= text.len or text[index] notin {'0' .. '9'}:
    return -1
  while index < text.len and text[index] in {'0' .. '9'}:
    inc index
  if index < text.len and text[index] == ',':
    inc index
    while index < text.len and text[index] == ' ':
      inc index
    if index >= text.len or text[index] notin {'0' .. '9'}:
      return -1
    while index < text.len and text[index] in {'0' .. '9'}:
      inc index
  if index < text.len and text[index] == ')':
    index + 1
  else:
    -1

proc extendHintLocation(text: string, span: var KosmoHintSpan) =
  ## Absorb a trailing Nim ``path(line[, column])`` group, including the
  ## space that splits ``f.nim(12, 5)`` across the pattern's word run.
  let complete = text.parseHintParenthesis(span.last)
  if complete > span.last:
    span.last = complete
  elif span.last - span.first > 2 and text[span.last - 1] == ',':
    var opener = -1
    for index in countdown(span.last - 2, span.first):
      if text[index] == '(':
        opener = index
        break
      if text[index] notin {'0' .. '9', ' '}:
        break
    if opener >= span.first:
      var tail = span.last
      while tail < text.len and text[tail] == ' ':
        inc tail
      if tail < text.len and text[tail] in {'0' .. '9'}:
        while tail < text.len and text[tail] in {'0' .. '9'}:
          inc tail
        if tail < text.len and text[tail] == ')':
          span.last = tail + 1

func isHintWordRune(value: Rune): bool =
  ## ASCII words, Kitty's word characters, and Unicode letters; Unicode
  ## digits outside ASCII stay unmatched.
  if value.ord < 128:
    let letter = char(value.ord)
    letter.isAlphaAscii() or letter in {'0' .. '9'} or letter in KosmoHintWordCharacters
  else:
    value.isAlpha()

proc wordHintSpans(text: string): seq[KosmoHintSpan] =
  ## Split text into selection-style word runs, like Kitty's word matcher.
  var
    start = -1
    cursor = 0
  for value in text.runes:
    if value.isHintWordRune():
      if start < 0:
        start = cursor
    elif start >= 0:
      result.add KosmoHintSpan(first: start, last: cursor)
      start = -1
    cursor += value.size
  if start >= 0:
    result.add KosmoHintSpan(first: start, last: cursor)

proc refineHintSpan(kind: KosmoHintKind, text: string, span: var KosmoHintSpan) =
  case kind
  of khkLink:
    text.truncateHintAtCloser(span)
    text.trimHintTail(span)
  of khkPath:
    text.trimHintEnclosure(span)
    text.extendHintLocation(span)
    text.trimHintTail(span)
  of khkWord, khkHash:
    discard

proc kosmoHintSpans*(
    kind: KosmoHintKind, text: string, workingDirectory = ""
): seq[KosmoHintText] =
  ## Match `text` for `kind`, returning trimmed snippets in reading order.
  ## Path hints must resolve to existing files; `workingDirectory` resolves
  ## relative locations.
  if text.len == 0:
    return
  var spans: seq[KosmoHintSpan]
  case kind
  of khkWord:
    spans = text.wordHintSpans()
  of khkLink:
    for match in hintLinkPattern().findMatches(text):
      spans.add KosmoHintSpan(first: match.first, last: match.last)
  of khkPath:
    for match in hintPathPattern().findMatches(text):
      spans.add KosmoHintSpan(first: match.first, last: match.last)
  of khkHash:
    for match in hintHashPattern().findMatches(text):
      spans.add KosmoHintSpan(first: match.first, last: match.last)
  for span in spans:
    var candidate = span
    kind.refineHintSpan(text, candidate)
    if candidate.last <= candidate.first:
      continue
    let snippet = text[candidate.first ..< candidate.last]
    if snippet.runeLen < KosmoHintMinimumRunes:
      continue
    if kind == khkPath:
      let location = nimkit.resolveTerminalFileLocation(snippet, workingDirectory)
      if location.isNone:
        continue
      result.add KosmoHintText(text: snippet, span: candidate, fileLocation: location)
    else:
      result.add KosmoHintText(text: snippet, span: candidate)

proc kosmoHintTexts*(kind: KosmoHintKind, text: string): seq[string] =
  ## Return the matched snippet texts for `kind`, in reading order.
  for candidate in kind.kosmoHintSpans(text):
    result.add candidate.text

func hintsToSkip(count, alphabetSize: int): int =
  ## Count of leading labels to drop so the assigned set stays prefix-free.
  let needed = max(count, 2)
  (needed - 2) div max(alphabetSize - 1, 1)

func encodeHintLabel*(index: int, alphabet = KosmoHintAlphabet): string =
  ## Encode `index` as a label in breadth-first prefix-tree order over
  ## `alphabet`: 0, 1, ..., 9, a, ..., z, 00, 01, ... for Kitty's alphabet.
  var number = index
  while number >= 0:
    result = alphabet[number mod alphabet.len] & result
    number = number div alphabet.len - 1

proc assignKosmoHintLabels*(hints: var seq[KosmoHint]) =
  ## Give hints prefix-free labels, shortest at the bottom like Kitty.
  if hints.len == 0:
    return
  let skip = max(1, hintsToSkip(hints.len, KosmoHintAlphabet.len))
  for index in 0 ..< hints.len:
    hints[hints.len - 1 - index].label = encodeHintLabel(index + skip)

proc collectMonoTextHints*(
    view: nimkit.MonoTextView,
    kind: KosmoHintKind,
    workingDirectory = "",
    firstRow = 0,
    lastRow = -1,
    firstColumn = 0,
): seq[KosmoHint] =
  ## Collect hints from a MonoTextView's rendered cell grid. Only matches
  ## whose cells intersect the view's bounds are returned, so hinting always
  ## follows the visible screen. `firstRow`, `lastRow` (half-open), and
  ## `firstColumn` restrict the grid to the surface's text area.
  if view.isNil:
    return
  let
    bounds = view.bounds()
    stop =
      if lastRow < 0:
        view.lineCount()
      else:
        min(lastRow, view.lineCount())
  for row in firstRow ..< stop:
    var
      rowText = ""
      textStartByte = -1
    for column in 0 ..< view.columnCount(row):
      if column == firstColumn:
        textStartByte = rowText.len
      var cellText = view.cellAt(row, column).text
      # Moe draws indentation guides as a vertical line glued to indented
      # text; treat them as whitespace so paths after leading blanks keep
      # resolving. The rune count is unchanged, so positions stay aligned.
      if cellText == "│":
        cellText = " "
      rowText.add cellText
    if textStartByte < 0 or textStartByte >= rowText.len:
      continue
    let
      matchText = rowText[textStartByte ..^ 1]
      baseRunes = rowText[0 ..< textStartByte].runeLen
      rowBase = view.lineRange(row).location
    var cursor: TextByteCursor
    for candidate in kind.kosmoHintSpans(matchText, workingDirectory):
      let
        first = matchText.runeIndexAtByte(cursor, candidate.span.first)
        last = matchText.runeIndexAtByte(cursor, candidate.span.last)
        startIndex = rowBase + baseRunes + first
      let markerRect = view.characterRect(startIndex)
      if markerRect.isEmpty:
        continue
      var matchRect = markerRect
      if last > first:
        let endRect = view.characterRect(rowBase + baseRunes + last - 1)
        if not endRect.isEmpty:
          matchRect = nimkit.rect(
            markerRect.minX,
            markerRect.minY,
            max(endRect.maxX - markerRect.minX, markerRect.w),
            markerRect.h,
          )
      if matchRect.intersection(bounds).isEmpty:
        continue
      result.add KosmoHint(
        text: candidate.text,
        matchRect: matchRect,
        markerRect: markerRect,
        fileLocation: candidate.fileLocation,
      )

proc collectTextViewHints*(
    textView: nimkit.TextView, kind: KosmoHintKind, workingDirectory = ""
): seq[KosmoHint] =
  ## Collect hints from a TextView's attributed text. Only matches with a
  ## laid-out position intersecting the view's visible rect are returned.
  if textView.isNil:
    return
  let layout = textView.layoutManager()
  if layout.isNil:
    return
  layout.updateLayout()
  let
    text = textView.stringValue()
    visible = textView.visibleRect()
  if text.len == 0:
    return
  var cursor: TextByteCursor
  for candidate in kind.kosmoHintSpans(text, workingDirectory):
    let
      first = text.runeIndexAtByte(cursor, candidate.span.first)
      last = text.runeIndexAtByte(cursor, candidate.span.last)
    let markerRect = textView.characterRect(first)
    if markerRect.isEmpty:
      continue
    var matchRect = markerRect
    for fragment in textView.selectionRects(nimkit.initTextRange(first, last - first)):
      matchRect = matchRect.union(fragment)
    if matchRect.intersection(visible).isEmpty:
      continue
    result.add KosmoHint(
      text: candidate.text,
      matchRect: matchRect,
      markerRect: markerRect,
      fileLocation: candidate.fileLocation,
    )

proc runKosmoHintAction*(
    hint: KosmoHint, action: KosmoHintAction, activation: KosmoHintActivation
): bool =
  ## Perform `action` on a selected hint. Returns false when the activation
  ## cannot run the action for this surface.
  case action
  of khaCopy:
    discard nimkit.generalPasteboard().replaceWithPlainText(hint.text)
    true
  of khaInsert:
    not activation.insertText.isNil and activation.insertText(hint.text)
  of khaOpen:
    if hint.fileLocation.isSome:
      not activation.openFile.isNil and activation.openFile(hint.fileLocation.get)
    else:
      not activation.openLink.isNil and activation.openLink(hint.text)

proc kosmoHintInView*(hint: KosmoHint, source, host: nimkit.View): KosmoHint =
  ## Reposition a hint collected on `source` into `host`'s coordinates, for
  ## hosts presenting hints gathered from several embedded text views.
  result = hint
  result.matchRect = source.rectToView(hint.matchRect, host)
  result.markerRect = source.rectToView(hint.markerRect, host)

proc hintOverlayForView*(view: nimkit.View): KosmoHintOverlay =
  ## Return the hint overlay currently presented on `view`.
  if not view.isNil:
    for child in view.subviews():
      if child of KosmoHintOverlay:
        return KosmoHintOverlay(child)

proc kosmoHintsVisible*(view: nimkit.View): bool =
  not view.hintOverlayForView().isNil

proc presentedHints*(overlay: KosmoHintOverlay): seq[KosmoHint] =
  ## The hints with labels as presented by `overlay`, for tests and inspection.
  if not overlay.isNil:
    result = overlay.xHints

proc dismissKosmoHints*(overlay: KosmoHintOverlay) =
  ## Remove markers and return keyboard focus to the hosting surface.
  if overlay.isNil or overlay.xDismissed:
    return
  overlay.xDismissed = true
  let
    owner = overlay.window()
    restore = overlay.xRestoreFirstResponder
    host = overlay.superview()
  if not host.isNil:
    host.disconnect(nimkit.geometryDidChange, overlay)
  if owner of nimkit.Window:
    nimkit.Window(owner).disconnect(nimkit.didResignKeyWindow, overlay)
  overlay.removeFromSuperview()
  if not restore.isNil and owner of nimkit.Window and not nimkit.Window(owner).isClosed():
    discard nimkit.Window(owner).makeFirstResponder(restore)

proc dismissKosmoHints*(host: nimkit.View) =
  host.hintOverlayForView().dismissKosmoHints()

proc hintHostGeometryDidChange(overlay: KosmoHintOverlay) {.slot.} =
  ## Dismiss markers once the host resizes, because text reflows.
  let host = overlay.superview()
  if host.isNil or host.bounds().size != overlay.xHostBoundsSize:
    overlay.dismissKosmoHints()

proc hintOverlayDidResignKey(overlay: KosmoHintOverlay) {.slot.} =
  overlay.dismissKosmoHints()

func hintCandidates(overlay: KosmoHintOverlay): seq[KosmoHint] =
  for hint in overlay.xHints:
    if hint.label.startsWith(overlay.xTyped):
      result.add hint

proc markerRectForHint(overlay: KosmoHintOverlay, index: int): nimkit.Rect =
  ## The marker chip rectangle for a hint, sized to fit its label.
  let hint = overlay.xHints[index]
  let size = nimkit.textNaturalSize(hint.label)
  nimkit.rect(
    hint.markerRect.minX, hint.markerRect.minY, size.width + 6.0'f32, hint.markerRect.h
  )

proc hintIndexAtPoint(overlay: KosmoHintOverlay, point: nimkit.Point): int =
  for index, hint in overlay.xHints:
    if hint.label.startsWith(overlay.xTyped) and
        overlay.markerRectForHint(index).contains(point):
      return index
  -1

proc activateHint(overlay: KosmoHintOverlay, hint: KosmoHint) =
  overlay.dismissKosmoHints()
  if not overlay.xOnActivate.isNil:
    overlay.xOnActivate(hint)

func labelCharacter(event: nimkit.KeyEvent): char =
  ## The label character a key event selects. Real backends deliver key events
  ## without text (the character follows as a separate text commit), so derive
  ## it from the key as well as the event text.
  if event.text.len == 1:
    event.text[0].toLowerAscii()
  else:
    case event.key
    of nimkit.keyA .. nimkit.keyZ:
      char(ord('a') + event.key.ord - nimkit.keyA.ord)
    of nimkit.key1 .. nimkit.key9:
      char(ord('1') + event.key.ord - nimkit.key1.ord)
    of nimkit.keyNumpad1 .. nimkit.keyNumpad9:
      char(ord('1') + event.key.ord - nimkit.keyNumpad1.ord)
    of nimkit.key0, nimkit.keyNumpad0:
      '0'
    else:
      '\0'

proc handleLabelCharacter(overlay: KosmoHintOverlay, value: char): bool =
  ## Feed one label character. Returns true when it was consumed.
  if value notin KosmoHintAlphabet:
    overlay.dismissKosmoHints()
    return true
  let typed = overlay.xTyped & value
  var
    matches = 0
    foundExact = false
    exact: KosmoHint
  for hint in overlay.xHints:
    if hint.label.startsWith(typed):
      inc matches
      if hint.label == typed:
        foundExact = true
        exact = hint
  if matches == 0:
    overlay.dismissKosmoHints()
  elif matches == 1 and foundExact:
    overlay.activateHint(exact)
  else:
    overlay.xTyped = typed
    overlay.needsDisplay = true
  true

proc handleHintKey(overlay: KosmoHintOverlay, event: nimkit.KeyEvent): bool =
  ## Consume label typing; any other key ends the hint session. Modifier
  ## combinations pass through after dismissal so shortcuts keep working.
  if event.modifiers - {nimkit.kmShift} != {}:
    overlay.dismissKosmoHints()
    return false
  # Real backends deliver the typed character as a separate text commit after
  # the key event. Claim that commit so the restored surface does not receive
  # the character a second time after the session handled it.
  let owner = overlay.window()
  if owner of nimkit.Window:
    nimkit.Window(owner).suppressShortcutText()
  if event.key == nimkit.keyEscape:
    overlay.dismissKosmoHints()
    return true
  if event.key == nimkit.keyBackspace:
    if overlay.xTyped.len > 0:
      overlay.xTyped.setLen(overlay.xTyped.len - 1)
      overlay.needsDisplay = true
    else:
      overlay.dismissKosmoHints()
    return true
  if event.key == nimkit.keyEnter:
    let candidates = overlay.hintCandidates()
    if candidates.len == 1:
      overlay.activateHint(candidates[0])
    return true
  overlay.handleLabelCharacter(event.labelCharacter())

protocol KosmoHintOverlayResponder of nimkit.ResponderProtocol:
  method acceptsFirstResponder(overlay: KosmoHintOverlay): bool =
    true

protocol KosmoHintOverlayDrawing of nimkit.ViewDrawingProtocol:
  method draw(overlay: KosmoHintOverlay, context: nimkit.DrawContext) =
    for index, hint in overlay.xHints:
      if not hint.label.startsWith(overlay.xTyped):
        continue
      discard context.addRectangle(
        hint.matchRect, nimkit.fill(nimkit.color(1.0, 0.78, 0.28, 0.20))
      )
      let chip = overlay.markerRectForHint(index)
      discard context.addRectangle(chip, nimkit.fill(nimkit.color(0.22, 0.72, 0.36, 1)))
      context.addText(
        nimkit.rect(chip.minX + 3.0'f32, chip.minY, chip.w - 6.0'f32, chip.h),
        hint.label,
        nimkit.color(0.06, 0.10, 0.07, 1.0),
        nimkit.taCenter,
      )

protocol KosmoHintOverlayEvents of nimkit.ResponderEventProtocol:
  method keyDown(overlay: KosmoHintOverlay, event: nimkit.KeyEvent): bool =
    overlay.handleHintKey(event)

  method mouseDown(overlay: KosmoHintOverlay, event: nimkit.MouseEvent): bool =
    let index = overlay.hintIndexAtPoint(event.location)
    if index >= 0:
      overlay.activateHint(overlay.xHints[index])
      return true
    overlay.dismissKosmoHints()
    false

  method scrollWheel(overlay: KosmoHintOverlay, event: nimkit.ScrollEvent): bool =
    ## Scrolling reflows positions; end the session and let the surface scroll.
    overlay.dismissKosmoHints()
    false

protocol KosmoHintOverlayInput of nimkit.TextInputProtocol:
  method insertText(overlay: KosmoHintOverlay, text: string) =
    ## Real backends deliver the character after the key event; the overlay
    ## already processed the key, so only IME-style commits feed labels.
    if overlay.xDismissed:
      return
    if text.len == 1:
      discard overlay.handleLabelCharacter(text[0])
    elif text.len > 1:
      overlay.dismissKosmoHints()

protocol KosmoHintOverlayCommands of nimkit.ResponderCommandDispatchProtocol:
  method interceptKeyEquivalent(
      overlay: KosmoHintOverlay, event: nimkit.KeyEvent
  ): bool =
    if event.modifiers - {nimkit.kmShift} == {}:
      return overlay.handleHintKey(event)
    overlay.dismissKosmoHints()
    false

proc presentKosmoHints*(
    host: nimkit.View,
    hints: seq[KosmoHint],
    onActivate: proc(hint: KosmoHint) {.closure.},
): bool {.discardable.} =
  ## Overlay labeled markers for `hints` on `host`, give the overlay keyboard
  ## focus, and run `onActivate` for the hint selected by label typing,
  ## clicking a marker, or pressing Return on a single remaining candidate.
  ## Returns false without side effects when there is nothing to present.
  if host.isNil or hints.len == 0:
    return false
  let owner = host.window()
  if not (owner of nimkit.Window) or nimkit.Window(owner).isClosed():
    return false
  host.dismissKosmoHints()
  var labeled = hints
  labeled.assignKosmoHintLabels()
  let overlay = KosmoHintOverlay(
    xHints: labeled, xOnActivate: onActivate, xHostBoundsSize: host.bounds().size
  )
  overlay.initViewFields()
  overlay.backgroundColor = nimkit.color(0.0, 0.0, 0.0, 0.0)
  overlay.frame = host.bounds()
  discard overlay.withProtocol(KosmoHintOverlayResponder)
  discard overlay.withProtocol(KosmoHintOverlayDrawing)
  discard overlay.withProtocol(KosmoHintOverlayEvents)
  discard overlay.withProtocol(KosmoHintOverlayInput)
  discard overlay.withProtocol(KosmoHintOverlayCommands)
  host.addSubview(overlay)
  host.connect(nimkit.geometryDidChange, overlay, hintHostGeometryDidChange)
  nimkit.Window(owner).connect(
    nimkit.didResignKeyWindow, overlay, hintOverlayDidResignKey
  )
  overlay.xRestoreFirstResponder = nimkit.Window(owner).firstResponder()
  result = nimkit.Window(owner).makeFirstResponder(nimkit.Responder(overlay))
  if not result:
    overlay.dismissKosmoHints()
