## Text formatting and parsing for generic resource property editors.

import std/[sequtils, strutils]

import ../foundation/types
import ../themes
import ./resourcecore

type ResourceValueParseResult* = object
  parsed*: bool
  value*: ResourceValue
  message*: string

func formatResourceFloat(value: float32): string =
  $value

func formatResourceValue*(value: ResourceValue): string =
  case value.kind
  of rvNone:
    ""
  of rvString:
    value.stringValue
  of rvInt:
    $value.intValue
  of rvFloat:
    value.floatValue.formatResourceFloat()
  of rvBool:
    $value.boolValue
  of rvStrings:
    value.stringValues.join(", ")
  of rvRect:
    [
      value.rectValue.origin.x, value.rectValue.origin.y, value.rectValue.size.width,
      value.rectValue.size.height,
    ]
    .mapIt(it.formatResourceFloat())
    .join(", ")
  of rvSize:
    [value.sizeValue.width, value.sizeValue.height].mapIt(it.formatResourceFloat()).join(
      ", "
    )
  of rvInsets:
    [
      value.insetsValue.top, value.insetsValue.left, value.insetsValue.bottom,
      value.insetsValue.right,
    ]
    .mapIt(it.formatResourceFloat())
    .join(", ")
  of rvColor:
    [value.colorValue.r, value.colorValue.g, value.colorValue.b, value.colorValue.a]
    .mapIt(it.formatResourceFloat())
    .join(", ")
  of rvReference:
    $value.referenceValue.kind & ":" & $value.referenceValue.id

proc parseFloatParts(text: string, expected: Positive): seq[float32] =
  let parts = text.split(',')
  if parts.len != expected:
    return
  try:
    for part in parts:
      result.add parseFloat(part.strip()).float32
  except ValueError:
    result.setLen(0)

proc parseResourceValueAs(
    text: string, kind: ResourceValueKind, preferred: ResourceValue
): ResourceValueParseResult =
  try:
    case kind
    of rvNone:
      if text.len == 0:
        result = ResourceValueParseResult(parsed: true)
    of rvString:
      result = ResourceValueParseResult(parsed: true, value: resourceValue(text))
    of rvInt:
      result = ResourceValueParseResult(
        parsed: true, value: resourceValue(parseInt(text.strip()))
      )
    of rvFloat:
      result = ResourceValueParseResult(
        parsed: true, value: resourceValue(parseFloat(text.strip()).float32)
      )
    of rvBool:
      case text.strip().toLowerAscii()
      of "true":
        result = ResourceValueParseResult(parsed: true, value: resourceValue(true))
      of "false":
        result = ResourceValueParseResult(parsed: true, value: resourceValue(false))
      else:
        discard
    of rvStrings:
      let values =
        if text.len == 0:
          newSeq[string]()
        else:
          text.split(',').mapIt(it.strip())
      result = ResourceValueParseResult(parsed: true, value: resourceValue(values))
    of rvRect:
      let values = text.parseFloatParts(4)
      if values.len == 4:
        result = ResourceValueParseResult(
          parsed: true,
          value: resourceValue(rect(values[0], values[1], values[2], values[3])),
        )
    of rvSize:
      let values = text.parseFloatParts(2)
      if values.len == 2:
        result = ResourceValueParseResult(
          parsed: true, value: resourceValue(initSize(values[0], values[1]))
        )
    of rvInsets:
      let values = text.parseFloatParts(4)
      if values.len == 4:
        result = ResourceValueParseResult(
          parsed: true,
          value: resourceValue(insets(values[0], values[1], values[2], values[3])),
        )
    of rvColor:
      let values = text.parseFloatParts(4)
      if values.len == 4:
        result = ResourceValueParseResult(
          parsed: true,
          value: resourceValue(color(values[0], values[1], values[2], values[3])),
        )
    of rvReference:
      let separator = text.find(':')
      if separator > 0:
        let referenceKind = parseEnum[ResourceReferenceKind](text[0 ..< separator])
        result = ResourceValueParseResult(
          parsed: true,
          value: resourceValue(
            resourceReference(referenceKind, resourceId(text[separator + 1 .. ^1]))
          ),
        )
      elif preferred.kind == rvReference and preferred.referenceValue.kind != rrNone:
        result = ResourceValueParseResult(
          parsed: true,
          value: resourceValue(
            resourceReference(preferred.referenceValue.kind, resourceId(text))
          ),
        )
  except ValueError:
    discard

proc parseResourceValue*(
    text: string, acceptedKinds: set[ResourceValueKind], preferred = ResourceValue()
): ResourceValueParseResult =
  ## Parses inspector text, retaining unparseable input as a string resource value.
  if preferred.kind in acceptedKinds or
      (acceptedKinds == {} and preferred.kind != rvNone):
    result = text.parseResourceValueAs(preferred.kind, preferred)
    if result.parsed:
      return

  for kind in ResourceValueKind:
    if kind in acceptedKinds and kind != preferred.kind:
      result = text.parseResourceValueAs(kind, preferred)
      if result.parsed:
        return

  if acceptedKinds == {} and preferred.kind == rvNone:
    return ResourceValueParseResult(parsed: true, value: resourceValue(text))

  result = ResourceValueParseResult(
    value: resourceValue(text),
    message: "input does not match any accepted resource-value kind",
  )
