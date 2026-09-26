# Changes

## Unreleased

- Drain temporary macOS menu and application-frame objects promptly, preventing
  long-running Kosmo sessions from retaining old native menus and growing by
  tens of gigabytes.
- Preserve unchanged Window-menu entries during keyboard shortcut checks instead
  of repeatedly rebuilding the native menu bar.
- Open Moe's `:config` viewer in a reusable Kosmo document tab, and show files
  opened with `:e` in native document tabs.
- Keep file previews and initial blank buffers owned by their pane when opening
  files from the sidebar or search, and reuse tabs already open in another pane.
- Make `kosmo --bg` open paths in a detached new instance, add foreground
  `--new`, and accept `-v` as an alias for `--version`.
- Move Kosmo's Files and Find controls into a taller status bar and let the
  sidebar collapse while preserving its width and using the active theme accent.
- Keep Kosmo's status text clear of the Files and Find icons.
- Let Kosmo launch a configured Nim language server through Moe's LSP client.
- Close unrelated inherited descriptors before the configured Nim server starts.
- Poll Git child output without waiting for inherited pipe writers to close.
- Release text views and active field editors after their owning windows close,
  clearing generated layout references and circular keyboard-navigation links.
- Keep layout-constraint view links non-owning so dismissed dialog content is
  released without discarding constraints needed by reusable windows.
- Use FigDraw 0.43.0 for render ownership and native window teardown.
- Expand Open and Save dialogs with a resizable file browser and fix closing
  edited Kosmo tabs after Discard.

## 0.22.0

- Disconnect stopped animation clocks before releasing their shared-thread proxies.
- Release closed panel button actions and response callbacks to avoid retaining
  dismissed dialog windows and their owners.
- Use the FigDraw 0.43.0 release for render ownership and GPU completion.
- Keep Kosmo window shortcuts available while a terminal tab has focus.
- Reject native control-character text events on X11, Wayland, and Windows to
  avoid duplicate editor input after Return and Delete key events.
- Share immutable UTF-8 text snapshots across NimKit text storage and FigDraw
  layout while preserving rune-based public APIs.
- Store styled text as byte and rune ranges with compact style IDs and sparse
  rune and line checkpoints.
- Add diagnostic RSS output to the large NimKit styled-text regression test.
- Avoid storage and TextView undo snapshots when undo is disabled; retain one
  prepared snapshot per grouped edit and report undo-mode RSS diagnostics.
- Apply syntax colors in one compact run-table edit, retokenize safe single-line
  changes locally, and use endpoint cursors instead of dense highlighting maps.
- Expose explicit UTF-8 byte ranges and allocation-free rune iteration on text
  snapshots while keeping rune-based editing ranges.
- Pack MonoText viewport rows into UTF-8 buffers and interned styles, and stream
  Moe and terminal rows into the viewport without full temporary cell grids.
  Grid replacement and scrolling now take row providers instead of owned cell
  arrays.
- Share immutable FigDraw glyph layouts with per-line range views, retain only
  one copy of aliased source/display UTF-8, and omit duplicate geometry arrays
  from frozen layouts. Large TextViews draw visible lines through the viewport.
