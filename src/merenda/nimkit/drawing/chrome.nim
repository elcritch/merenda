import std/options

from figdraw/figbasics import ZLevel
from figdraw/fignodes import FigIdx

import sigils/core
import sigils/selectors

import ./drawing
import ./theme
import ../foundation/types

type
  ChromeRole* = enum
    crButton
    crChoiceIndicator
    crCheckBoxIndicator
    crRadioIndicator
    crComboBox
    crPopupList
    crTab
    crTabPanel

  ChromePart* = enum
    cpFace
    cpInnerFace
    cpGloss
    cpLowerWash
    cpHighlight
    cpSeam
    cpArrow
    cpSeparator

  ChromeEdge* = enum
    ceNone
    ceTop
    ceBottom

  ChromeContext* = object
    name*: string
    role*: ChromeRole
    part*: ChromePart
    states*: set[WidgetState]
    baseFill*: Fill

  ChromeExtras* = object
    layer*: ZLevel
    parent*: FigIdx
    rect*: Rect
    cornerRadius*: float32
    edge*: ChromeEdge
    seamFill*: Fill
    highlightFill*: Fill

var fallbackDefaultChrome {.threadvar.}: Chrome

protocol ChromeProtocol:
  method chromeFillFor*(context: ChromeContext): Fill {.optional.}

  method drawChromeExtrasFor*(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
  ) {.optional.}

func transparentFill(): Fill =
  fill(initColor(0.0, 0.0, 0.0, 0.0))

func chromeContext*(
    name: string,
    role: ChromeRole,
    part: ChromePart,
    baseFill: Fill,
    states: set[WidgetState] = {},
): ChromeContext =
  ChromeContext(name: name, role: role, part: part, states: states, baseFill: baseFill)

func initChromeExtras*(
    parent: FigIdx,
    rect: Rect,
    layer = DefaultDrawLevel,
    cornerRadius = 0.0'f32,
    edge = ceNone,
    seamFill = transparentFill(),
    highlightFill = transparentFill(),
): ChromeExtras =
  ChromeExtras(
    layer: layer,
    parent: parent,
    rect: rect,
    cornerRadius: cornerRadius,
    edge: edge,
    seamFill: seamFill,
    highlightFill: highlightFill,
  )

protocol DefaultChromeProtocol of ChromeProtocol:
  method chromeFillFor(chrome: Chrome, context: ChromeContext): Fill =
    context.baseFill

  method drawChromeExtrasFor(
      chrome: Chrome,
      context: DrawContext,
      chromeContext: ChromeContext,
      extras: ChromeExtras,
  ) =
    discard chrome
    discard context
    discard chromeContext
    discard extras

proc newDefaultChrome*(): Chrome =
  result = Chrome()
  discard result.withProtocol(DefaultChromeProtocol)

proc defaultChrome(): Chrome =
  if fallbackDefaultChrome.isNil:
    fallbackDefaultChrome = newDefaultChrome()
  fallbackDefaultChrome

proc resolveChrome*(theme: Theme, name: string): Chrome =
  result = theme.chrome(name)
  if result.isNil:
    result = defaultChrome()

proc resolveChrome*(appearance: Appearance, name: string): Chrome =
  appearance.theme.resolveChrome(name)

proc chromeFill*(theme: Theme, context: ChromeContext): Fill =
  theme.resolveChrome(context.name).trySendLocal(chromeFillFor(), context).get(
    context.baseFill
  )

proc chromeFill*(appearance: Appearance, context: ChromeContext): Fill =
  appearance.theme.chromeFill(context)

proc drawChromeExtras*(
    context: DrawContext, chrome: ChromeContext, extras: ChromeExtras
) =
  discard context.appearance.resolveChrome(chrome.name).sendLocalIfHandled(
      drawChromeExtrasFor(), (context: context, chrome: chrome, extras: extras)
    )

proc installDefaultChrome(theme: var Theme) =
  theme.installChrome(DefaultChromeName, defaultChrome())

registerThemeInstaller(installDefaultChrome)
