## Shared theme destinations, independent of the settings UI.

type KosmoThemeTarget* {.pure.} = enum
  All
  Moe
  Terminal
  RichText
  Markdown
  GitDiff
  GitHub

const KosmoRichTextTargets* =
  [KosmoThemeTarget.Markdown, KosmoThemeTarget.GitDiff, KosmoThemeTarget.GitHub]

func themeTargetIncludes*(target, item: KosmoThemeTarget): bool =
  ## Whether applying a theme to target includes the individual item.
  case target
  of KosmoThemeTarget.All:
    item in {
      KosmoThemeTarget.Moe, KosmoThemeTarget.Terminal, KosmoThemeTarget.Markdown,
      KosmoThemeTarget.GitDiff, KosmoThemeTarget.GitHub,
    }
  of KosmoThemeTarget.RichText:
    item in
      {KosmoThemeTarget.Markdown, KosmoThemeTarget.GitDiff, KosmoThemeTarget.GitHub}
  else:
    item == target
