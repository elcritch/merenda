## Scoped shortcut routing for Kosmo terminal panes.

import std/strutils
import ../nimkit/foundation/events
import ./panekeys

export panekeys

type
  KosmoTerminalInputPolicy* {.pure.} = enum
    Hybrid
    Raw

  TerminalShortcutState* = object
    panePrefix: bool
    rawNext: bool
    rawPaneContinuation: bool
    prefixEvent: KeyEvent

  TerminalKeyRouteKind* = enum
    tkrPass
    tkrConsume
    tkrPane
    tkrCopy
    tkrPaste
    tkrRaw

  TerminalKeyRoute* = object
    kind*: TerminalKeyRouteKind
    command*: KosmoPaneCommand
    keys*: seq[KeyEvent]

func terminalInputPolicyName*(policy: KosmoTerminalInputPolicy): string =
  case policy
  of KosmoTerminalInputPolicy.Hybrid: "hybrid"
  of KosmoTerminalInputPolicy.Raw: "raw"

func parseTerminalInputPolicy*(value: string): KosmoTerminalInputPolicy =
  ## Unknown or missing configuration uses the default Hybrid policy.
  if value.toLowerAscii() == "raw":
    KosmoTerminalInputPolicy.Raw
  else:
    KosmoTerminalInputPolicy.Hybrid

proc reset*(state: var TerminalShortcutState) =
  state = TerminalShortcutState()

func isControlKey(event: KeyEvent, key: Key): bool =
  event.key == key and event.modifiers == {kmControl}

proc routeTerminalKey*(
    state: var TerminalShortcutState,
    event: KeyEvent,
    policy: KosmoTerminalInputPolicy,
    panesEnabled = true,
    interceptClipboard = not (defined(macosx) or defined(macos)),
): TerminalKeyRoute =
  ## Ctrl-backslash quotes the next shortcut, including a Ctrl-W continuation.
  ## Escape cancels a pending prefix; unknown Ctrl-W sequences are forwarded intact.
  if policy == KosmoTerminalInputPolicy.Raw:
    state.reset()
    if kmControl in event.modifiers:
      return TerminalKeyRoute(kind: tkrRaw, keys: @[event])
    return
  if state.rawNext or state.rawPaneContinuation:
    let firstQuotedKey = state.rawNext
    state.rawNext = false
    state.rawPaneContinuation = false
    if event.key == keyEscape and event.modifiers == {}:
      return TerminalKeyRoute(kind: tkrConsume)
    state.rawPaneContinuation = firstQuotedKey and event.isControlKey(keyW)
    return TerminalKeyRoute(kind: tkrRaw, keys: @[event])
  if state.panePrefix:
    state.panePrefix = false
    if event.key == keyEscape and event.modifiers == {}:
      return TerminalKeyRoute(kind: tkrConsume)
    let command = event.paneCommand()
    if command != kpcNone:
      return TerminalKeyRoute(kind: tkrPane, command: command)
    return TerminalKeyRoute(kind: tkrRaw, keys: @[state.prefixEvent, event])
  if event.isControlKey(keyBackslash):
    state.rawNext = true
    return TerminalKeyRoute(kind: tkrConsume)
  if panesEnabled and event.isControlKey(keyW):
    state.panePrefix = true
    state.prefixEvent = event
    return TerminalKeyRoute(kind: tkrConsume)
  if interceptClipboard:
    if event.isControlKey(keyC):
      return TerminalKeyRoute(kind: tkrCopy)
    if event.isControlKey(keyV):
      return TerminalKeyRoute(kind: tkrPaste)
