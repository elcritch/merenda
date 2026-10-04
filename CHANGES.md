# Changes

## Unreleased

- Resolve the Git diff panel's key-equivalent selector explicitly so Kosmo builds
  with Nim devel when menu and window procedures use the same name.

- Let standalone Kosmo connect to a TCP LSP endpoint by setting `nimLspCommand`
  to `tcp://host:port`, forwarding framed protocol bytes through its LSP child
  process and closing the connection when the session ends.
- Route menu navigation keys to the active popup before the focused panel.
  Keep up/down movement within the current menu and submenu, and move left/right
  through the visible menubar order consistently, fixing Kosmo issues #129 and #130.
  Tab and Shift+Tab close the active popup and cycle key focus through the
  menu bar buttons, opening each menu as focus reaches it, and continue with
  the remaining key views past the menu bar. Arrow navigation between menus
  moves key focus with the open menu, and menu bar buttons draw a focus ring
  while they hold visible keyboard focus, resolving its color from the
  theme's focus ring color token like the other controls.
- Keep Tab and Shift+Tab moving focus after combo-box and context-menu popup
  dismissal, and preserve normal key-view traversal for popup lists without a
  custom Tab handler.

- Move reusable terminal sessions, Sigils commands, RChan snapshots, and the
  dedicated worker dispatcher into Terminex 0.4.0's optional threaded adapter.
  NimKit retains viewports, rendering, and native event-loop integration; the
  Terminex parser, synchronous PTY API, and snapshot helpers also work without
  Sigils or threads.

- Keep terminal updates and animation deadlines running during native macOS menu
  tracking and modal panels. Rearm worker wake notifications consumed by AppKit
  so opening About does not leave terminals updating in slow chunks afterward.
- Give terminal workers exclusive session ownership. Send commands through Sigils
  and transfer bounded, owned snapshots through RChan, removing parser mutexes
  and UI lock-priority retries. Keep parsing independent of presentation while
  transferring only newly retained history. All view sessions use this worker
  path, including offline parsing and Windows builds; native Windows PTY startup
  still needs a ConPTY backend in Terminex.
- Track deferred terminal UI callbacks with `BackRef` so queued work cannot
  dereference a destroyed view during ORC collection.
- Terminal view mutations are now asynchronous. Use `newTerminalViewSession()` or
  `spawnTerminalViewSession()` instead of passing raw Terminex sessions to views.
  Queries return the last received snapshot; `poll()` consumes available updates,
  and `pendingCommands()` reports outstanding commands. Closing marks the facade
  closed immediately and queues process cleanup on the worker.

- Batch matching terminal glyph styles within each changed row and skip blank
  glyphs while retaining their backgrounds and decorations. Defer frame
  construction while the renderer is occupied, and schedule the first terminal
  update after idle without an extra batching delay.

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
- Pin Moe to upstream develop at `22c74002`, including the host result hook
  merged in PR #3332, so Ex commands, runtime mappings, and Filer split-open
  requests can use Kosmo's document tabs and dock panes.
- Route `:split`/`:vsplit` and `:new`/`:vnew` to Kosmo panes, preserving the
  source buffer and cursor. Keep interactive Config state in a reusable tab
  without a hidden Moe split, and honor Moe runtime mappings for Ctrl-W.
- Dispatch ambiguous Moe key mappings from Kosmo's idle poll when their
  configured timeout expires.
- Consolidate macOS workspace watches into FSEvents streams for whole trees,
  preventing nested folders in multiple projects from exhausting dmon's global
  watch limit. Deduplicate roots, report fallback causes and uncovered paths,
  and retry registration when missing directories or capacity become available.
- Keep Tab and Shift-Tab in Kosmo editor search controls from reaching the
  underlying editor's insert, replace, or command mode.
- Add configurable FigDraw backdrop blur to Box containers and use it behind
  Kosmo's search overlay, with a themed tint for readable controls.
- Render push-button toggle state consistently and give enabled search regex
  buttons a pressed accent appearance. Support vector icons in standard Buttons
  so search disclosure and navigation arrows remain visible across fonts.
- Use standard text fields, buttons, and Box chrome in Kosmo search panels.
  Fix replacement-field clicks and placeholder alignment, put the expression
  toggle first after the query in tab order, and contain overlay clicks.
- Add TextField placeholders and compact toolbar styling for Buttons.
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

- Pause automatic layout retries after sixteen consecutive unsettled NimKit
  transactions, retaining the warning at three cycles and the pending work.
  Per-root feedback limits are configurable; new external layout input retries
  blocked roots without letting layout callbacks reset their own limit.
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
