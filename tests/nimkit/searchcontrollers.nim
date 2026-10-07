import std/[options, strutils, unittest]

import merenda/nimkit

suite "NimKit reusable search":
  test "adapters search multiple sources, retain navigation, and detach cleanly":
    let
      host = newView(frame = rect(0, 0, 640, 360))
      window = newWindow("Reusable search", frame = host.frame())
    var sources = @["λcat cat", "DOG cat"]
    var unavailable = false
    var revealed: TextSearchLocation
    var cleared = 0
    let search = newTextSearchController(
      host,
      "records",
      TextSearchAdapter(
        sources: proc(): seq[string] =
          if unavailable:
            raise newException(IOError, "Records unavailable")
          sources,
        reveal: proc(match: TextSearchLocation) =
          revealed = match,
        clear: proc() =
          inc cleared
        ,
      ),
    )
    defer:
      search.close()
      window.close()
    window.setContentView(host)
    require search.showSearch()
    require window.dispatchTextInput("cat")
    check search.searchMatchCount() == 3
    check revealed == TextSearchLocation(source: 0, range: initTextRange(1, 3))
    search.findNext()
    check revealed == TextSearchLocation(source: 0, range: initTextRange(5, 3))
    search.findNext()
    check revealed == TextSearchLocation(source: 1, range: initTextRange(4, 3))
    search.findNext()
    check revealed.source == 0
    search.findNext(backwards = true)
    check revealed.source == 1
    sources.add "cat"
    search.refreshSearch()
    check search.searchMatchCount() == 4
    check revealed.source == 1
    search.bar.regularExpression = true
    search.bar.queryField().selectedRange = initTextRange(0, 3)
    require window.dispatchTextInput("[")
    check search.searchMatchCount() == 0
    check search.errorMessage().startsWith("Search error:")
    check cleared > 0
    search.bar.queryField().selectedRange = initTextRange(0, 1)
    require window.dispatchTextInput(r"(?<=λ)cat")
    check search.searchMatchCount() == 1
    check search.errorMessage() == ""
    unavailable = true
    search.refreshSearch()
    check search.searchMatchCount() == 0
    check search.errorMessage() == "Search error: Records unavailable"
    unavailable = false
    search.refreshSearch()
    check search.searchMatchCount() == 1
    check search.errorMessage() == ""
    check search.bar.replacementField().isNil
    search.close()
    check search.bar.superview().isNil
    check not search.searchVisible()
    # Retaining the bar after its controller closes must not call old adapters.
    search.bar.regularExpression = false

  test "replacement adapters receive validated captures and empty replacement text":
    let
      host = newView(frame = rect(0, 0, 640, 360))
      window = newWindow("Reusable replacement", frame = host.frame())
    var source = "λcat dog cat"
    var replaceCalls = 0
    let search = newTextSearchController(
      host,
      "editable records",
      TextSearchAdapter(
        sources: proc(): seq[string] =
          @[source],
        replace: proc(
            pattern: TextSearchPattern,
            replacement: TextSearchReplacement,
            selected: Option[TextSearchLocation],
            all: bool,
        ): int =
          inc replaceCalls
          let original = source
          let ranges = pattern.searchRanges(original)
          var matches: seq[TextSearchMatch]
          for match in pattern.findMatches(original):
            matches.add match
          for index in countdown(matches.high, 0):
            if all or (selected.isSome and ranges[index] == selected.get.range):
              let match = matches[index]
              source =
                source[0 ..< match.first] & replacement.expand(match, original) &
                source[match.last ..< source.len]
              inc result
        ,
      ),
    )
    defer:
      search.close()
      window.close()
    window.setContentView(host)
    require search.showSearch(replacing = true)
    check search.bar.replacementVisible
    search.bar.regularExpression = true
    require window.dispatchTextInput("(?<animal>cat|dog)")
    search.bar.replacementField().text = "${missing}"
    check search.replaceMatch(all = true) == 0
    check replaceCalls == 0
    check source == "λcat dog cat"
    check search.errorMessage().startsWith("Replacement error:")
    search.bar.replacementField().text = "${animal}!"
    check search.replaceMatch() == 1
    check source == "λcat! dog cat"
    check search.errorMessage() == ""
    search.bar.replacementField().text = ""
    check search.replaceMatch(all = true) == 3
    check source == "λ!  "
    check search.searchMatchCount() == 0

  test "TextView adapter selects Unicode text without replacement controls":
    let
      host = newView(frame = rect(0, 0, 640, 360))
      text = newTextView("λcat DOG")
      window = newWindow("TextView adapter", frame = host.frame())
      search = newTextSearchController(host, "text", textViewSearchAdapter(text))
    defer:
      search.close()
      window.close()
    host.addSubview(text)
    window.setContentView(host)
    require search.showSearch()
    require window.dispatchTextInput("cat")
    check text.selectedRange() == initTextRange(1, 3)
    check text.selectedText() == "cat"
    check search.bar.replacementField().isNil
    search.dismissSearch()
    check text.selectedRange().length == 0
    expect ValueError:
      discard newTextSearchController(host, "missing", TextSearchAdapter())
