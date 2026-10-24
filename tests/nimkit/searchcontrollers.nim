import std/[options, strutils, unittest]

import merenda/nimkit

suite "NimKit reusable search":
  test "floating search tolerates collapsed hosts and releases its constraints":
    let
      host = newView(frame = rect(0, 0, 0, 0))
      originalConstraints = host.constraints().len
      search = newTextSearchController(
        host,
        "records",
        TextSearchAdapter(
          sources: proc(): seq[string] =
            @["needle"]
        ),
      )
    defer:
      search.close()
    search.bar.hidden = false
    for size in [initSize(0, 0), initSize(16, 20), initSize(640, 360)]:
      host.frame = rect(initPoint(0, 0), size)
      host.layoutSubtreeIfNeeded()
      let frame = search.bar.frame()
      check frame.minX >= -0.01
      check frame.minY >= -0.01
      check frame.maxX <= size.width + 0.01
      check frame.maxY <= size.height + 0.01
      check not host.layoutFeedbackBlocked()
    check search.bar.frame().size.width == SearchBarWidth
    search.close()
    check host.constraints().len == originalConstraints
    host.layoutSubtreeIfNeeded()
    check not host.needsLayout()

  test "floating search respects narrow hosts and settles after error transitions":
    for width in [320.0'f32, 400.0'f32]:
      let
        host = newView(frame = rect(0, 0, width, 240))
        window = newWindow("Narrow floating search", frame = host.frame())
        search = newTextSearchController(
          host,
          "records",
          TextSearchAdapter(
            sources: proc(): seq[string] =
              @["needle"]
          ),
        )
      defer:
        search.close()
        window.close()
      window.setContentView(host)
      require search.showSearch()
      search.bar.regularExpression = true
      var normalHeight: float32
      for query in ["needle", "[", "needle", "[", "needle"]:
        require window.dispatchKeyDown(
          KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: shortcutModifiers())
        )
        require window.dispatchTextInput(query)
        host.layoutSubtreeIfNeeded()
        discard window.buildRenders()
        let frame = search.bar.frame()
        check frame.minX == SearchBarInset
        check frame.maxX == width - SearchBarInset
        check frame.size.width == width - SearchBarInset * 2
        if query == "[":
          check search.bar.errorMessage().len > 0
          check frame.size.height > normalHeight
        elif normalHeight == 0:
          normalHeight = frame.size.height
        else:
          check frame.size.height == normalHeight
        let generation = host.layoutGeneration()
        discard window.buildRenders()
        check host.layoutGeneration() == generation
        check not host.layoutFeedbackBlocked()

  test "embedded search bars leave their frame under their container's control":
    let
      host = newView(frame = rect(0, 0, 800, 480))
      window = newWindow("Embedded search", frame = host.frame())
      embeddedFrame = rect(24, 120, 480, 120)
      bar = newSearchBar(frame = embeddedFrame)
    defer:
      bar.close()
      window.close()
    host.addSubview(bar)
    window.setContentView(host)
    bar.hidden = false
    bar.frame = embeddedFrame
    bar.enableExpressions()
    bar.enableReplacement(nil, nil)
    host.layoutSubtreeIfNeeded()
    check bar.frame() == embeddedFrame
    require window.makeFirstResponder(bar.queryField())
    require window.dispatchTextInput("ensureArrangement")
    for message in ["Search error: incomplete expression", ""]:
      bar.errorMessage = message
      host.layoutSubtreeIfNeeded()
      check bar.frame() == embeddedFrame
      check bar.query() == "ensureArrangement"
    for expanded in [true, false]:
      bar.replacementVisible = expanded
      host.layoutSubtreeIfNeeded()
      check bar.frame() == embeddedFrame
      check bar.query() == "ensureArrangement"

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
