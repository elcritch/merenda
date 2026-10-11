## Typed attribute conversion shared by the HTML resource importer.

import std/[math, strutils]

import ../../foundation/types
import ../../themes/themecore
import ../[resrccore, resrcregistry]

func attributeKey*(name: string): string =
  name.toLowerAscii().replace("-", "")

proc finiteNumber(text: string): float32 =
  result = parseFloat(text).float32
  if classify(result) in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "expected a finite number")

proc numbers(text: string): seq[float32] =
  for item in text.split({' ', '\t', '\r', '\n', ','}):
    if item.len > 0:
      result.add finiteNumber(item)

proc htmlRect*(text: string): Rect =
  let values = numbers(text)
  if values.len != 4:
    raise newException(ValueError, "expected x, y, width, height")
  rect(values[0], values[1], values[2], values[3])

func enumSuffix(name: string): string =
  for index, ch in name:
    if ch in {'A' .. 'Z'}:
      return name[index ..^ 1].attributeKey()
  name.attributeKey()

proc htmlValue*(text: string, descriptor: ResourcePropertyDescriptor): ResourceValue =
  let kinds = descriptor.acceptedKinds
  if rvString in kinds:
    if descriptor.options.len == 0:
      return resourceValue(text)
    for option in descriptor.options:
      if option.kind == rvString and (
        text.attributeKey() == option.stringValue.attributeKey() or
        text.attributeKey() == option.stringValue.enumSuffix()
      ):
        return option
    raise
      newException(ValueError, "unknown value '" & text & "' for " & descriptor.name)
  elif rvBool in kinds:
    case text.toLowerAscii()
    of "", "true", "1":
      return resourceValue(true)
    of "false", "0":
      return resourceValue(false)
    else:
      raise newException(ValueError, "expected true or false")
  elif rvFloat in kinds:
    return resourceValue(finiteNumber(text))
  elif rvInt in kinds:
    return resourceValue(parseInt(text))
  elif rvStrings in kinds:
    return resourceValue(text.splitWhitespace())
  elif rvRect in kinds:
    return resourceValue(htmlRect(text))
  elif rvSize in kinds:
    let values = numbers(text)
    if values.len == 2:
      return resourceValue(initSize(values[0], values[1]))
    raise newException(ValueError, "expected width, height")
  elif rvInsets in kinds:
    let values = numbers(text)
    case values.len
    of 1:
      return resourceValue(insets(values[0]))
    of 2:
      return resourceValue(insets(values[0], values[1], values[0], values[1]))
    of 4:
      return resourceValue(insets(values[0], values[3], values[2], values[1]))
    else:
      raise newException(ValueError, "expected 1, 2, or 4 CSS padding values")
  elif rvColor in kinds:
    if text.strip().len == 0:
      raise newException(ValueError, "expected a color")
    return resourceValue(parseHtmlColor(text))
  elif rvReference in kinds and descriptor.nimTypeName == "ImageResource" and
      text.startsWith("#") and text.len > 1:
    return resourceValue(resourceReference(rrImage, resourceId(text[1 ..^ 1])))
  raise newException(
    ValueError, "unsupported attribute value type: " & descriptor.nimTypeName
  )
