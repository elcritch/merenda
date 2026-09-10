import std/[unicode, unittest]

import figdraw

import merenda/nimkit
import merenda/kosmo/kosmo

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

proc checkVisibleText(view: View, expected: openArray[string]) =
  let renders = buildRenders(view)
  require DefaultDrawLevel in renders
  for text in expected:
    var found = false
    for index, node in renders[DefaultDrawLevel].nodes:
      if node.kind != nkText or node.renderedText() != text:
        continue
      found = true
      require node.textLayout.spanColors.len > 0
      check node.textLayout.spanColors[0].color.a > 0'u8
      check node.textLayout.bounding.x >= -0.1'f32
      check node.textLayout.bounding.y >= -0.1'f32
      check node.textLayout.bounding.x + node.textLayout.bounding.w <=
        node.screenBox.w + 0.1'f32
      check node.textLayout.bounding.y + node.textLayout.bounding.h <=
        node.screenBox.h + 0.1'f32
    if not found:
      checkpoint "Missing rendered settings text: " & text
    check found

suite "Kosmo settings layout":
  test "uses a compact stable minimum and keeps every page legible":
    let settings = newKosmoSettingsWindow(
      shortcuts = [
        KosmoShortcutSetting(
          action: "Save", description: "Save the active document", keys: "Ctrl+S"
        )
      ],
      textMateGrammars = [
        KosmoTextMateGrammar(
          name: "Nim",
          scopeName: "source.nim",
          origin: KosmoTextMateGrammarOrigin.BuiltIn,
        )
      ],
    )
    defer:
      settings.window().close()

    let window = settings.window()
    window.setContentView(settings.contentView())
    check not window.automaticallyAdjustsContentMinSize()
    check window.contentMinSize() ==
      initSize(KosmoSettingsMinimumWidth, KosmoSettingsMinimumHeight)

    window.frame = rect(180, 160, 660, 360)
    settings.contentView().layoutSubtreeIfNeeded()
    check window.frame().size == initSize(660, 360)
    check settings.contentView().frame().size == initSize(660, 360)

    let tabsView =
      settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier)
    require not tabsView.isNil
    require tabsView of TabView
    let tabs = TabView(tabsView)

    let expectedPageText = @[
      @[
        "Terminal", "Use Option/Alt-B and Option/Alt-F to move by words in Bash.",
        "Hold the platform link modifier while hovering a URL to reveal and open it.",
      ],
      @[
        "Active Shortcuts",
        "Changes apply immediately; edit bindings in keybindings.json.",
      ],
      @[
        "Moe Theme",
        "Choose a bundled theme or a TOML theme installed in ~/.config/moe/themes.",
      ],
      @[
        "TextMate Grammars",
        "These grammars are available to Moe and Markdown syntax highlighting.",
      ],
    ]
    for pageIndex, pageText in expectedPageText:
      check tabs.selectTabViewItemAtIndex(pageIndex)
      settings.contentView().layoutSubtreeIfNeeded()
      check tabs[pageIndex].view().frame().size.width > 0.0'f32
      check tabs[pageIndex].view().frame().size.height > 0.0'f32
      settings.contentView().checkVisibleText(pageText)

    window.frame = rect(180, 160, 700, 390)
    check window.frame().size == initSize(700, 390)
    window.frame = rect(180, 160, 610, 330)
    check window.frame().size ==
      initSize(KosmoSettingsMinimumWidth, KosmoSettingsMinimumHeight)
