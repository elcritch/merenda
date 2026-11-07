import std/[random, unittest]

import figdraw
import merenda/nimkit/text/textruneutils

suite "text rune boundary queries":
  test "streamed string queries match indexed Unicode and malformed input":
    var inputs = @[
      "", "alpha beta", "  one\t two  ", "café κόσμος 😀_x", "a\xF0z",
      "a\xFF b", "\xC0\xA0test", "abc\xE2\x82", "a\xF8\x80\x80\x80\x80 b",
      "a\xED\xA0\x80_b",
    ]
    var random = initRand(20261106)
    for sample in 0 ..< 300:
      var text = ""
      for index in 0 ..< random.rand(24):
        text.add char(random.rand(255))
      inputs.add text
    for text in inputs:
      let indexed = utf8RunesForText(text)
      for index in -2 .. indexed.len + 2:
        check text.previousWordBoundary(index) == indexed.previousWordBoundary(index)
        check text.nextWordBoundary(index) == indexed.nextWordBoundary(index)
        check text.wordRangeAt(index) == indexed.wordRangeAt(index)
