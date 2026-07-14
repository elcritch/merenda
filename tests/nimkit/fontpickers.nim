import std/[sequtils, strutils, unittest]

import merenda/nimkit

suite "NimKit font pickers":
  test "font catalog groups faces into stable families":
    let catalog = buildFontCatalog(
      [
        "/fonts/Arial Bold.ttf", "/fonts/Arial Italic.ttf", "/fonts/Arial.ttf",
        "/fonts/IBMPlexSans-BoldItalic.otf", "/fonts/IBMPlexSans-Regular.otf",
        "/fonts/Avenir Next Condensed Bold.ttf", "/fonts/Avenir Next Condensed.ttc",
      ]
    )

    check catalog.mapIt(it.family) ==
      @["Arial", "Avenir Next Condensed", "IBM Plex Sans"]
    check catalog[0].path == "/fonts/Arial.ttf"
    check catalog[1].path == "/fonts/Avenir Next Condensed.ttc"
    check catalog[2].path == "/fonts/IBMPlexSans-Regular.otf"
    check catalog[0].identifier == "system-font:arial"
    check "Arial Bold" in catalog[0].searchText
    check "IBM Plex Sans Bold Italic" in catalog[2].searchText
    check catalog[0].faces.mapIt(it.style) == @["Regular", "Italic", "Bold"]

  test "font catalog groups language variants and preserves their faces":
    let catalog = buildFontCatalog(
      [
        "/fonts/IBMPlexSans-Regular.otf", "/fonts/IBMPlexSans-Bold.otf",
        "/fonts/IBMPlexSansArabic-Regular.otf", "/fonts/IBMPlexSansArabic-Bold.otf",
        "/fonts/IBMPlexSansHebrew-Regular.otf", "/fonts/IBMPlexSansJP-Bold.otf",
        "/fonts/Bangla MN-Regular.ttf",
      ]
    )

    check catalog.mapIt(it.family) == @["Bangla MN", "IBM Plex Sans"]
    check catalog[0].faces.mapIt(it.language & ":" & it.style) == @["Bengali:Regular"]
    check catalog[1].path == "/fonts/IBMPlexSans-Regular.otf"
    check catalog[1].faces.mapIt(it.language & ":" & it.style) ==
      @[
        "Default:Regular", "Default:Bold", "Arabic:Regular", "Arabic:Bold",
        "Hebrew:Regular", "Japanese:Bold",
      ]
    check "IBM Plex Sans Arabic Bold" in catalog[1].searchText

  test "font options are built only when requested":
    var entries: seq[FontCatalogEntry]
    for index in 0 ..< 1_000:
      entries.add initFontCatalogEntry(
        "Family " & $index, "/fonts/family-" & $index & ".ttf"
      )

    let
      source = newFontCatalogDataSource(entries)
      comboBox = newComboBox()
    comboBox.dataSource = source

    check comboBox.numberOfItems() == 1_001
    check source.cachedOptionCount() == 0

    comboBox.selectedIndex = 0
    check source.cachedOptionCount() == 1
    check comboBox.itemAtIndex(500) == "Family 499"
    check source.cachedOptionCount() == 2
    check comboBox.itemAtIndex(500) == "Family 499"
    check source.cachedOptionCount() == 2

    comboBox.optionFilterText = "family 999"
    check comboBox.numberOfItems() == 1
    check source.cachedOptionCount() == 2
    check comboBox.itemAtIndex(0) == "Family 999"
    check source.cachedOptionCount() == 3

    comboBox.sizingMode = cbsmWidestItem
    discard comboBox.sizeThatFits()
    check source.cachedOptionCount() == 3
