import sigils/selectors

import ../foundation/events
import ../foundation/selectors as nimkitSelectors
import ../view/views

type
  ViewSelectionHandler* = proc(view: View, event: MouseEvent) {.closure.}

  ViewSelectionOptions* = object
    includeRoot*: bool
    consumeUnhandledClicks*: bool

  ViewSelection* = object
    xRoot: View
    xTokens: seq[tuple[view: View, token: SwizzleToken]]
    xInstalled: bool

func initViewSelectionOptions*(
    includeRoot = true, consumeUnhandledClicks = true
): ViewSelectionOptions =
  ViewSelectionOptions(
    includeRoot: includeRoot, consumeUnhandledClicks: consumeUnhandledClicks
  )

proc root*(selection: ViewSelection): View =
  selection.xRoot

proc installed*(selection: ViewSelection): bool =
  selection.xInstalled

proc installOnSubtree(
    selection: var ViewSelection,
    view: View,
    handler: ViewSelectionHandler,
    options: ViewSelectionOptions,
    includeSelf: bool,
) =
  if view.isNil:
    return

  if includeSelf:
    let
      callback = handler
      consumesUnhandled = options.consumeUnhandledClicks
      wrapper: AroundMethod = proc(
          self: DynamicAgent, invocation: var Invocation, next: DynamicMethod
      ) =
        var originalConsumed = false
        if not next.isNil:
          next(self, invocation)
          if invocation.handled:
            originalConsumed = invocation.resultAs(bool)

        let event = invocation.argsAs(MouseEvent)
        if event.button != mbPrimary:
          return

        if not callback.isNil:
          callback(View(self), event)

        if consumesUnhandled and not originalConsumed:
          invocation.setResult(true)

    selection.xTokens.add (
      view: view,
      token: DynamicAgent(view).pushMethod(nimkitSelectors.mouseDown(), wrapper),
    )

  for child in view.subviews:
    selection.installOnSubtree(child, handler, options, includeSelf = true)

proc installViewSelection*(
    root: View, handler: ViewSelectionHandler, options = initViewSelectionOptions()
): ViewSelection =
  if root.isNil:
    return

  result.xRoot = root
  result.xInstalled = true
  result.installOnSubtree(root, handler, options, options.includeRoot)

proc uninstall*(selection: var ViewSelection): bool {.discardable.} =
  if not selection.xInstalled:
    return

  for idx in countdown(selection.xTokens.high, 0):
    result = selection.xTokens[idx].token.popMethod() or result
  selection.xTokens.setLen(0)
  selection.xRoot = nil
  selection.xInstalled = false
