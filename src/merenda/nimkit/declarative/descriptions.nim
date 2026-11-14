## Value descriptions for the first declarative NimKit view prototype.
## Builders may be evaluated repeatedly. Event callbacks run only on live mounts.
import ../foundation/types
import ../themes
import ../containers/stackviews
import ../text/textfields
import ./actions
export actions except dispatchViewAction

type
  ViewSpecKind* = enum
    vskStack
    vskLabel
    vskButton
    vskTextField

  ViewSpec* = object
    ## Keys are sibling-scoped identities; identifiers are ordinary view names.
    ## `slot` is assigned by `viewBody` for structural identity. Zero uses child position.
    key*: string
    slot*: int
    identifier*: string
    draggable*: bool
    sizing*: StackViewSizingPolicy
    background*: Color
    text*: string
    case kind*: ViewSpecKind
    of vskStack:
      orientation*: LayoutAxis
      spacing*: float32
      padding*: EdgeInsets
      alignment*: StackViewAlignment
      distribution*: StackViewDistribution
      children*: seq[ViewSpec]
    of vskLabel:
      labelStyle*: LabelStyle
    of vskButton:
      enabled*: bool
      focusable*: bool
      onAction*: ViewAction
    of vskTextField:
      placeholder*: string
      onChange*: ViewAction

proc vstackSpec*(
    children: seq[ViewSpec] = @[],
    spacing = 8.0'f32,
    padding = insets(0),
    alignment = svaFill,
    distribution = svdNatural,
    key = "",
    identifier = "",
    draggable = false,
    background = color(0, 0, 0, 0),
    sizing = svspAutomatic,
): ViewSpec =
  ViewSpec(
    kind: vskStack,
    children: children,
    orientation: laVertical,
    spacing: spacing,
    padding: padding,
    alignment: alignment,
    distribution: distribution,
    key: key,
    identifier: identifier,
    draggable: draggable,
    background: background,
    sizing: sizing,
  )

proc hstackSpec*(
    children: seq[ViewSpec] = @[],
    spacing = 8.0'f32,
    padding = insets(0),
    alignment = svaFill,
    distribution = svdNatural,
    key = "",
    identifier = "",
    draggable = false,
    background = color(0, 0, 0, 0),
    sizing = svspAutomatic,
): ViewSpec =
  result = vstackSpec(
    children, spacing, padding, alignment, distribution, key, identifier, draggable,
    background, sizing,
  )
  result.orientation = laHorizontal

proc labelSpec*(
    text: string, style = lsBody, key = "", identifier = "", sizing = svspAutomatic
): ViewSpec =
  ViewSpec(
    kind: vskLabel,
    text: text,
    labelStyle: style,
    key: key,
    identifier: identifier,
    sizing: sizing,
  )

proc buttonSpec*(
    text: string,
    onAction = ViewAction(),
    enabled = true,
    focusable = true,
    key = "",
    identifier = "",
    sizing = svspAutomatic,
): ViewSpec =
  ViewSpec(
    kind: vskButton,
    text: text,
    onAction: onAction,
    enabled: enabled,
    focusable: focusable,
    key: key,
    identifier: identifier,
    sizing: sizing,
  )

proc textFieldSpec*(
    value: string,
    onChange = ViewAction(),
    placeholder = "",
    key = "",
    identifier = "",
    sizing = svspAutomatic,
): ViewSpec =
  ViewSpec(
    kind: vskTextField,
    text: value,
    onChange: onChange,
    placeholder: placeholder,
    key: key,
    identifier: identifier,
    sizing: sizing,
  )

proc keyedSpec*(key: string, child: ViewSpec): ViewSpec =
  ## Give a component's root explicit identity without creating another widget.
  if key.len == 0:
    raise newException(ValueError, "declarative keys must not be empty")
  result = child
  result.key = key
