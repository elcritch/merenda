## Kosmo's NimKit application, editor panes, and workspace orchestration.

when not defined(features.merenda.kosmo):
  {.
    error:
      """
Kosmo requires the "kosmo" feature. Enable it with Atlas:

  atlas install -tuk --features:kosmo
"""
  .}

import std/[math, options, os, strutils, unicode]

import ../nimkit as nimkit
from ../nimkit/foundation/mainthreadwork import scheduleMainThreadWork
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ../nimkit/foundation/selectors as nimkitSelectors
import
  ./[
    applicationassets, cliopen, config, contextpanel, filesearchpanel, filetree,
    gitdiff, inputtranslation, matterworkers, moe, moehighlighting, panedocuments,
    quickopen, searchbar, settings, shortcutpresentation, shortcuts, terminalsearch,
    workspacefiles,
  ]

export
  cliopen, config, contextpanel, filesearchpanel, filetree, gitdiff, moe,
  moehighlighting, panedocuments, quickopen, settings, shortcuts, terminalsearch
export applicationassets except configureKosmoApplicationAssets
export shortcutpresentation except focusPanelNumber

const
  KosmoTabBarHeight* = 34.0'f32
  KosmoStatusBarHeight* = 22.0'f32
  KosmoCommandBarHeight* = 24.0'f32
  KosmoQuickOpenTopInset = 96.0'f32
  KosmoQuickOpenBottomInset = 24.0'f32
  KosmoEditorStyleId* = "kosmo.editor"
  KosmoPaneIndicatorStyleId* = "kosmo.pane-indicator"
  KosmoMarkdownControlsStyleId* = "kosmo.markdown-controls"
  KosmoMarkdownControlButtonStyleClass = "kosmo-markdown-control-button"
  KosmoPreviewTabStyleClass* = "kosmo-preview"
  KosmoMarkdownDefaultFontSize* = 14.0'f32
  KosmoMarkdownPreviewCacheLimit = 3
  KosmoMarkdownMinimumFontSize* = 9.0'f32
  KosmoMarkdownMaximumFontSize* = 28.0'f32
  KosmoInactivePaneStyleClass* = "kosmo-inactive-pane"
  KosmoCursorOpacity = 0.45'f32
  KosmoPaneOutlineOpacity = 0.38'f32
  KosmoInactiveTabAccentOpacity = 0.18'f32
  KosmoInactiveTabTextOpacity = 0.72'f32
  KosmoPaneOutlineWidth = 1.0'f32
  KosmoMarkdownControlsWidth = 184.0'f32
  KosmoMarkdownControlsHeight = 38.0'f32
  KosmoMarkdownControlsInset = 10.0'f32
  KosmoMarkdownFontSizeIncrement = 1.0'f32
  KosmoControlScrollMultiplier = 3.0'f32
  KosmoGridOverscanRows = 1
  KosmoMoeBottomAreaRows = 1
  KosmoTabIdentifierPrefix = "kosmo.buffer."
  KosmoTerminalIdentifierPrefix = "kosmo.terminal."
  KosmoFilesTabIdentifier* = "kosmo.sidebar.files"
  KosmoFindTabIdentifier* = "kosmo.sidebar.find"
  KosmoFilesIconSvg =
    """<svg width="24" height="24" viewBox="0 0 24 24"><path fill="#000" d="M2 5h8l2 2h10v13H2z"/></svg>"""
  KosmoFindIconSvg =
    """<svg width="24" height="24" viewBox="0 0 24 24"><circle cx="10" cy="10" r="6" fill="none" stroke="#000" stroke-width="2.4"/><path fill="#000" d="M14.2 13l7 7-1.7 1.7-7-7z"/></svg>"""

# Shared type declarations remain in the facade's lexical scope so implementation
# fragments can keep private fields private and avoid artificial module cycles.
include application_types
include application_editor
include application_dock
include application_windows
