## Shared Vim pane commands for editors, previews and hybrid terminals.

import ../nimkit/foundation/events

type KosmoPaneCommand* = enum
  kpcNone
  kpcSplitBelow
  kpcSplitRight
  kpcNewBelow
  kpcFocusNext
  kpcFocusPrevious
  kpcFocusLeft
  kpcFocusBelow
  kpcFocusAbove
  kpcFocusRight
  kpcClose
  kpcGrowHeight
  kpcShrinkHeight
  kpcShrinkWidth
  kpcGrowWidth
  kpcEqualize

func paneCommand*(event: KeyEvent): KosmoPaneCommand =
  ## Interpret the continuation of Ctrl-W, including Vim's Control aliases.
  let modifiers = event.modifiers
  if modifiers - {kmControl, kmShift} != {}:
    return
  if event.key in keyA .. keyZ:
    if kmShift in modifiers:
      if event.key == keyW:
        return kpcFocusPrevious
      return
    case event.key
    of keyS: kpcSplitBelow
    of keyV: kpcSplitRight
    of keyN: kpcNewBelow
    of keyW: kpcFocusNext
    of keyH: kpcFocusLeft
    of keyJ: kpcFocusBelow
    of keyK: kpcFocusAbove
    of keyL: kpcFocusRight
    of keyC: kpcClose
    else: kpcNone
  else:
    case event.key
    of keyArrowLeft:
      kpcFocusLeft
    of keyArrowDown:
      kpcFocusBelow
    of keyArrowUp:
      kpcFocusAbove
    of keyArrowRight:
      kpcFocusRight
    of keyEqual:
      if kmShift in modifiers or event.text == "+": kpcGrowHeight else: kpcEqualize
    of keyMinus:
      kpcShrinkHeight
    of keyComma:
      if kmShift in modifiers or event.text == "<": kpcShrinkWidth else: kpcNone
    of keyDot:
      if kmShift in modifiers or event.text == ">": kpcGrowWidth else: kpcNone
    else:
      kpcNone
