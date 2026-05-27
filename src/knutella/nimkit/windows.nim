from figdraw/fignodes import Renders

import ./rendering as nimkitRendering
import ./selectors
import ./types
import ./views

type Window* = ref object
  xFrame: Rect
  xTitle: string
  xContentView: View
  xFirstResponder: Responder

proc newWindow*(frame: Rect, title: string): Window =
  Window(xFrame: frame, xTitle: title)

proc newWindow*(x, y, width, height: float32, title: string): Window =
  newWindow(initRect(x, y, width, height), title)

proc frame*(window: Window): Rect =
  window.xFrame

proc title*(window: Window): string =
  window.xTitle

proc contentView*(window: Window): View =
  window.xContentView

proc setContentView*(window: Window, view: View) =
  window.xContentView = view

proc firstResponder*(window: Window): Responder =
  window.xFirstResponder

proc makeFirstResponder*(window: Window, responder: Responder): bool =
  if not responder.isNil and not responder.acceptsFirstResponder():
    return false
  if not window.xFirstResponder.isNil:
    if not window.xFirstResponder.resignFirstResponder():
      return false
  if not responder.isNil and not responder.becomeFirstResponder():
    return false
  window.xFirstResponder = responder
  true

proc buildRenders*(window: Window): Renders =
  nimkitRendering.buildRenders(window.xContentView)

proc clickAt*(window: Window, point: Point): bool =
  if window.xContentView.isNil:
    return false
  window.xContentView.clickAt(point)

proc dispatchKeyDown*(window: Window, event: KeyEvent): bool =
  if not window.xFirstResponder.isNil:
    var value: EmptyArgs
    if window.xFirstResponder.perform(
      keyDownSelector(), KeyEventArgs(event: event), value
    ):
      return true
  if window.xContentView.isNil:
    return false
  window.xContentView.dispatchKeyDown(event)
