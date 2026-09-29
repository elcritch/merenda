# Changes

## Unreleased

- Make `BackRef` a reference object with shared registrations and independent
  rebinding. Read and assign targets through `handle.target`, replacing `handle[]`.
- Save Kosmo configuration and Tekton resource documents through checked
  temporary files and atomic replacement, preserving existing contents when a
  write or close fails.
- Keep generated layout equations from retaining views and give back references
  stable registrations across returns, copies, and sequence moves, so laid-out
  standalone and detached trees release under ARC and ORC.
- Apply streamed Markdown syntax colors with indexed range updates and local
  run changes, preserving quote styles, undo, and edit notifications while
  reducing work on large documents.
- Add an opt-in `.*` mode for Reni expressions and replacement captures in Kosmo
  editor and file search. Default both fields to literal text; validate capture
  templates before editing, handle engine limits, and render matches in Kosmo
  without modifying the Moe dependency.
- Default Kosmo editor and file search to compact search-only controls. Reveal
  replacement with the disclosure chevron or by adding Option/Alt to the search
  shortcut; regular search shortcuts collapse replacement and preserve the query.
- Add replacement of search matches to Kosmo editor panes and Find in Files,
  with grouped editor undo, checked atomic file saves, stale-result validation,
  and protection for unsaved buffers.
- Add plain-text search to Markdown and Git diff viewers, including collapsed diff
  sections, and center editor search matches through Kosmo's Moe adapter.

- Add `nim install_kosmo` to build and install the current checkout as a complete
  macOS app bundle, using the release icon and resources.
- Read terminal output in bounded application-frame work and coalesce grid
  updates on fixed deadlines, keeping input and rendering responsive during
  output bursts without adding a continuous idle frame timer.
- Stop polling healthy idle PTYs; retain readiness notifications and slow
  maintenance for cursor blinking, pending input, and exit after hangup.
- Add an opt-in native terminal timing trace and standalone/Kosmo benchmarks.
  The terminal scheduler uses Terminex's budgeted polling and EOF distinction.
- Keep Kosmo terminal clipboard shortcuts on the focused terminal when window
  shortcuts use the same keys, and pass bare Ctrl+A/C/X/V through as terminal
  input even where the window binds those keys to editing commands.

- Refresh cached MonoText rows when horizontal scrolling exposes new columns,
  and recapture drawing slots that depend on changed view bounds.
- Transfer only changed scroll transforms and view ordering to the renderer,
  including correct placement of retained explicit drawing layers.
- Reuse Git diff section geometry while scrolling and avoid invalidating
  unchanged headers, including offscreen headers.
- Keep opened Git diff sections loaded when they scroll out of view, preserving
  selection and layout until collapse. Large diffs still require an explicit open.
- Preserve the file browser's pixel scroll position across filesystem and Git
  refreshes, including partially visible selected rows and the end of the list.
  Keep the same files and selection in place when rows above the viewport change.
- Stream Matter syntax colors into Moe in bounded row batches, retaining
  multiline state and rejecting results from superseded edits.
- Display Markdown structure before code highlighting completes, then patch
  code colors in place while preserving selection and embedded code views.
- Reuse cached text layout for color-only edits and refresh visible glyph colors
  without reshaping text or replacing shared glyph geometry.
- Use Matter 0.5.1's ARC ownership fix so discarded highlighting caches release
  recursive compiled grammars, including grammars retained by saved jobs.
- Release streamed code source copies promptly, map unquoted Markdown code with
  one range, and index code presentations by their highlighting request.
- Decorate URI underlines within incoming Kosmo highlighting batches to avoid
  repeatedly copying the completed highlight prefix.

- Blink the terminal cursor only while its view and window are focused, and avoid
  rebuilding the terminal grid when only the cursor changes.
- Watch terminal PTY readiness on POSIX instead of polling every animation frame,
  retaining a slower maintenance tick for blinking, pending input, and child exit.
  Release watch descriptors when terminals close, change sessions, or detach.

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
