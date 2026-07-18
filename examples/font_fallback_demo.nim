## Demonstrates UI and monospace font roles with automatic script fallback.

import merenda/nimkit

import sigils/selectors

from figdraw/common/fonttypes import figdrawTextBackend

const AutomaticFallbackEnabled =
  figdrawTextBackend == "harfbuzzy" or figdrawTextBackend == "hybrid"

const ScriptSamples =
  """
Latin: Hello, world!
Greek: Καλημέρα κόσμε
Cyrillic: Привет, мир
Arabic: مرحباً بالعالم
Hebrew: שלום עולם
Hindi: नमस्ते दुनिया
Japanese: こんにちは世界
Simplified Chinese: 你好，世界
Symbols and text emoji: ★ ✓ → ∑ ♫ ☕︎ ☺︎
"""

proc newScriptSamples(): TextStorage =
  result = newTextStorage(ScriptSamples)
  result.setAttributes(
    initTextRange(0, result.storageLength()), defaultTextAttributes(fontSize = 18.0)
  )
  for (line, language) in [
    (0, "en-US"),
    (1, "el"),
    (2, "ru"),
    (3, "ar"),
    (4, "he"),
    (5, "hi-IN"),
    (6, "ja-JP"),
    (7, "zh-Hans"),
  ]:
    result.setAttributes(
      result.storageLineRange(line),
      defaultTextAttributes(fontSize = 18.0, language = initLanguageTag(language)),
    )

let
  app = sharedApplication()
  window = newWindow("NimKit Font Fallback", frame = rect(140, 100, 820, 600))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel(
    when AutomaticFallbackEnabled:
      "Two font choices, automatic fallback"
    else:
      "Two font choices with the lightweight Pixie backend"
  )
  summary = newStatusLabel(
    when AutomaticFallbackEnabled:
      "HarfBuzz selects script and symbol faces automatically."
    else:
      "Pixie uses the Interface and Monospace faces without language-aware fallback."
  )
  settingsButton = newButton("Open Font Settings…")
  scriptsTitle = newHeadingLabel(
    when AutomaticFallbackEnabled:
      "Interface role with language-aware shaping"
    else:
      "Interface role"
  )
  scripts = newTextEditor(frame = rect(0, 0, 760, 300), richText = true, wraps = true)
  monospaceTitle = newHeadingLabel(
    when AutomaticFallbackEnabled:
      "Monospace role with the same automatic fallback"
    else:
      "Monospace role"
  )
  monospace = newMonoTextViewer(
    "let greeting = \"Hello, 世界 ☕︎\"\necho greeting & \" — Καλημέρα\"",
    frame = rect(0, 0, 760, 76),
  )
  openSettingsAction = actionSelector("openFontSettings")

proc openFontSettings(sender: DynamicAgent) =
  discard sender
  app.showMerendaSettings()

scripts.attributedText = newScriptSamples()
scripts.editable = false
scripts.selectable = true
scripts.textInsets = insets(12.0, 14.0, 12.0, 14.0)

monospace.fontSize = 15.0
monospace.padding = 12.0

settingsButton.target = newActionTarget(openSettingsAction, openFontSettings)
settingsButton.action = openSettingsAction

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(
  title, summary, settingsButton, scriptsTitle, scripts, monospaceTitle, monospace
)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 24.0, 28.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

app.runWindow(window, root)
