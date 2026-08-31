## Parsing for the safe subset of raw HTML used by Markdown image tags.

import std/strutils

from markdownpkg/entities import htmlEntityToUtf8

type MarkdownHtmlImage* = object
  url*: string
  alt*: string
  title*: string
  width*: float32
  height*: float32

func isHtmlSpace(character: char): bool =
  character in {' ', '\t', '\n', '\r', '\f'}

func isAttributeNameStart(character: char): bool =
  character in {'a' .. 'z', 'A' .. 'Z', '_', ':'}

func isAttributeName(character: char): bool =
  character.isAttributeNameStart() or character in {'0' .. '9', '.', '-'}

proc skipHtmlSpace(html: string, index: var int) =
  while index < html.len and html[index].isHtmlSpace():
    inc index

proc decodeHtmlAttribute(value: string): string =
  var index = 0
  while index < value.len:
    if value[index] != '&':
      result.add value[index]
      inc index
      continue

    let entityEnd = value.find(';', index + 1)
    if entityEnd < 0 or entityEnd - index > 64:
      result.add value[index]
      inc index
      continue

    let
      encoded = value[index .. entityEnd]
      decoded = htmlEntityToUtf8(encoded)
    if decoded.len == 0:
      result.add encoded
    else:
      result.add decoded
    index = entityEnd + 1

func parseHtmlDimension(value: string): float32 =
  if value.len == 0:
    return
  var parsed = 0.0
  for character in value:
    if character notin {'0' .. '9'}:
      return
    parsed = parsed * 10.0 + float64(ord(character) - ord('0'))
    if parsed > float64(high(float32)):
      return
  if parsed > 0.0:
    result = float32(parsed)

proc parseMarkdownHtmlImage*(html: string, image: var MarkdownHtmlImage): bool =
  ## Parse one complete HTML `img` tag without interpreting any other HTML.
  var index = 0
  html.skipHtmlSpace(index)
  if index >= html.len or html[index] != '<':
    return
  inc index

  let tagStart = index
  while index < html.len and html[index] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '-'}:
    inc index
  if html[tagStart ..< index].toLowerAscii() != "img":
    return

  var hasSource = false
  while index < html.len:
    html.skipHtmlSpace(index)
    if index >= html.len:
      return
    if html[index] == '>':
      inc index
      break
    if html[index] == '/' and index + 1 < html.len and html[index + 1] == '>':
      index += 2
      break
    if not html[index].isAttributeNameStart():
      return

    let attributeStart = index
    inc index
    while index < html.len and html[index].isAttributeName():
      inc index
    let attributeName = html[attributeStart ..< index].toLowerAscii()
    html.skipHtmlSpace(index)

    var value: string
    if index < html.len and html[index] == '=':
      inc index
      html.skipHtmlSpace(index)
      if index >= html.len:
        return
      if html[index] in {'\'', '"'}:
        let quote = html[index]
        inc index
        let valueStart = index
        while index < html.len and html[index] != quote:
          inc index
        if index >= html.len:
          return
        value = html[valueStart ..< index]
        inc index
      else:
        let valueStart = index
        while index < html.len and not html[index].isHtmlSpace() and html[index] != '>' and
            not (html[index] == '/' and index + 1 < html.len and html[index + 1] == '>'):
          inc index
        if valueStart == index:
          return
        value = html[valueStart ..< index]
      value = value.decodeHtmlAttribute()

    case attributeName
    of "src":
      if not hasSource:
        image.url = value
        hasSource = true
    of "alt":
      image.alt = value
    of "title":
      image.title = value
    of "width":
      image.width = value.parseHtmlDimension()
    of "height":
      image.height = value.parseHtmlDimension()
    else:
      discard

  html.skipHtmlSpace(index)
  hasSource and image.url.len > 0 and index == html.len
