# Changes

## Unreleased

- Make `nim install_kosmo` use macOS CI's runtime-loaded HarfBuzz/FriBidi
  libraries, bundled and signed inside the app with their license notices.

- Use FigDraw 0.46.3 and Harfbuzzy 0.6.0 for optional runtime text-library
  loading. Kosmo uses HarfBuzz shaping and automatic system-font fallback when
  supported libraries are present, and Pixie otherwise. Preserve native shaping
  in static builds and update bundled-library overrides for macOS and Windows.
- Switch Windows CI examples and Kosmo releases back to MinGW-w64 GCC. Bundle
  the UCRT64 text DLLs and their dependencies, retain DWARF debug information,
  and check startup without compiler tools on `PATH`. Update Siwin for FigDraw's
  Windows Vulkan-to-OpenGL fallback API. Remove the private patched Nim installer
  and its fork-specific atomics checks; Windows builds use the official compiler.

## 0.29.3

- Prefer opening editor tabs in a pane not displaying a terminal, with a Kosmo
  Settings option to always use the active pane.
- Open working-tree files directly from their Git diff headers in Kosmo.

- Document that installing dependencies needs a newer Atlas than the one bundled
  with Nim 2.2.12.
- Build bundled HarfBuzz/FriBidi libraries with Zig for static Linux musl
  releases.
- Require FigDraw 0.46.3 or newer and update Siwin for Windows presentation,
  retaining background development windows. Build bundled HarfBuzz/FriBidi
  libraries with Zig for static Linux musl releases.
- Open a pull request's base-to-head comparison in Kosmo from its GitHub view.
  Fetch PR refs in the background, including fork PRs, without changing the working branch.

## 0.29.2

- Fix terminal underline artifacts and cursor jumps in Claude Code by updating
  Terminex's handling of private keyboard control sequences.
- Keep Backspace and cursor movement in the focused terminal search field instead
  of forwarding those keys to the running terminal process.
- Handle large numeric terminal parameters, colon colors, ignored escape strings,
  and saved cursor state safely through the updated Terminex parser.

## 0.29.1

- Publish Linux, FreeBSD, and macOS release assets without waiting for Windows,
  then add Windows in a separate upload job while preserving the shared checksum list.

- Keep Git diff toolbar symbols visible in Punch's compact buttons. Give the
  GitHub viewer the same Refresh icon at the toolbar's right edge.

- Keep separate Git diff viewers for different projects, including detached windows.
  Reuse each project's viewer and refresh all open viewers without retargeting another project.

- Open existing terminal file paths in Kosmo with Command-click on macOS or
  Control-click on Linux and Windows. Support `filename:line:column` and Nim's
  `filename(line, column)` / `filename(line)` diagnostics in both terminal links
  and CLI arguments, including forwarded and background launches. Resolve terminal
  paths using the terminal's directory and support OSC file hyperlinks.

- Prevent stuck modifiers after macOS screenshot capture by using refreshed native
  modifier flags instead of stale cached key presses.

## 0.29.0

- Let Kosmo’s focused file tree use unmodified `h/j/k/l` as left/down/up/right
  arrows while keeping filter typing and shifted display shortcuts intact.

- Move Kosmo Git diff’s Working Tree choice into the ending revision-state menu.
  Show `^*` on its button and the checked-out branch in the branch selector.
  Choosing another branch returns to its tip; choosing Working Tree returns to
  the checked-out branch.

- Close the focused auxiliary window when using Kosmo’s close shortcuts or menu
  actions, including Merenda Settings and Kosmo Settings.

- Add the Punch theme, adapted from RUI2, with cream and orange colors, thick ink
  outlines, bold uppercase button captions, and hard shadows that depress on press.
  Select it in Settings or with `NIMKIT_THEME=punch`. Keep combo box arrow panels
  inside thick borders so the accent fill preserves the surrounding outline, and
  inset dropdown rows to preserve the popup border and rounded corners.
- Keep Peachy button hover and accent hover colors in its warm palette instead of
  inheriting Aqua blue, including Kosmo’s Git diff refresh button.

- Duplicate the HTML GUI demo with NIF interface and stylesheet files, preserving
  its preferences, Preview/Reset actions, theme switching, and About window. The
  theme uses native selector nodes, numeric lengths, keywords, and token references.
  Use the optional `nifDemo` Atlas feature with OpenParser 0.4.1 or newer. NIF
  numbers support hexadecimal, octal, binary, and digit separators; quoted strings
  accept literal `#`, `:`, and `;`. Restore the working example vocabulary and
  preserve short colors, leading zeros, and alpha in hexadecimal color literals.
  Add a matching shorthand demo with native widget properties, ComboBox options,
  and line-based style rules with grouped borders, chrome, and token references.

- Move NimKit table modules into `nimkit/tables/`. Direct module imports now use
  `nimkit/tables/tableviews` and `nimkit/tables/tablebasics`; `merenda/nimkit`
  continues to export the public table APIs.

- Route development control through Sigils JSON-RPC selectors and dispatcher over
  the private Unix socket. Keep asynchronous captures behind bounded result handles
  and allow modal callbacks or shutdown to reenter polling safely.
- Add `merenda-dev theme-load --file PATH` and `theme-reload` for live CSS changes.
  Add Refresh theme below the font choice in Merenda Settings to reread the selected
  bundled theme's CSS inheritance chain while preserving fonts. Failed loads keep
  the current appearance. `MERENDA_THEME_CSS_DIR` selects an alternate source directory.

- Add opt-in `-d:merenda.devControl` automation with explicit PID/socket addressing,
  renderer PNG screenshots, window inspection, pointer/key/text input, and a small
  CLI suitable for future MCP adapters.
- Add `MERENDA_BACKGROUND=1` nonactivating development presentation on macOS and
  Windows through a pinned Siwin update.

## 0.28.0

- Let locally signed macOS apps load their bundled text libraries. Check startup
  after signing and through the installed command to catch loader failures.
  Statically link HarfBuzz and FriBidi when installing with `nim install_kosmo`.

- Build Windows Kosmo releases and examples with MSVC. Use the Windows SDK
  resource compiler, ship the matching PDB, and keep Nim stack traces with
  function names and source lines in place of GNU libbacktrace on MSVC.
  Use Sigils 0.32.0 and a private Nim 2.2.10 compiler built with pinned,
  checksum-verified fixes for MSVC atomic exchange, compare-and-swap,
  arithmetic operations, and large ARC/ORC string literals in embedded assets.
  Invoke MSVC directly from its Developer shell so large linker response files
  remain within Windows' command-line limit.

- Enable FigDraw's `textBackendHarfbuzzy` Atlas feature in `merenda.nimble` so
  this checkout and downstream Merenda apps use HarfBuzz text rendering and
  automatic system-font fallback. Require released FigDraw 0.45.0 and Harfbuzzy
  0.3.0 for dynamic and static builds. Previously HarfBuzz was installed as a dependency,
  but FigDraw still selected Pixie, leaving automatic fallback disabled. Missing
  glyphs in the editor, terminal, and other text views can now use system fonts,
  including checkbox symbols absent from the bundled Nerd Font. Initialize fallback
  on background text-layout threads as well as the main thread.

- Render Markdown task lists with ☐ for `[ ]`, ☑ for `[x]` or `[X]`, and ☒ for
  `[-]`, preserving nested lists, numbering, and inline formatting.

- Match split divider fills, edges, and grips to each bundled theme's palette,
  including the dark Nebula, Peachy, and Synthwave83 themes.

- Tone down Aqua status labels with muted sage-gray surfaces, quieter shadows,
  and darker text.

- Give thin SplitView dividers an 8-pixel grab area, including macOS and macOS
  Dark, so dragging near either pane edge resizes the split reliably.

- Support CSS variable fallbacks such as `var(--accent, royalblue)`, including
  nested fallbacks, composite values, and empty substitutions. Revalidate them
  when root variables change while retaining cycle and expansion limits.

- Run Kosmo's GitHub CLI through the user's login shell on macOS and Linux, so
  apps opened from the desktop can find `gh` installed through shell profiles.
  Preserve the project directory and noninteractive GitHub settings after startup.
- Split Git diff comparison controls into branch and history dropdowns, with
  an ellipsis between the two sides. Keep branch menus free of ancestor entries,
  preserve history depth when switching branches, and wrap the toolbar in narrow
  panes so history values stay visible.

- Add Cmd-J (Ctrl-J with the platform shortcut profile on Windows/Linux) to
  focus an existing terminal, including hidden tabs and detached windows, or
  open a terminal in the nearest pane to the right. Create a right split when
  no pane is available. Keep New Terminal available for additional terminals.

- Draw the Git diff refresh control with a vector icon so it remains visible
  with every UI font, and fit Auto-refresh's label and switch to their content
  with a smaller gap.

- Keep the status-bar keymode tied to the global editor key-routing policy,
  mapping Vim and Hybrid to Moe and Native to normal. Opening read-only viewers
  and toggling forced text entry preserve the selected keymode.

- Reserve popup menu columns for checkmarks, shortcuts, and submenu indicators
  so they do not overlap titles. Measure menu contents instead of forcing small
  menus to be 180 pixels wide.

- Show project-relative paths in Find in Files tooltips, including match locations
  and Load more rows. Use the closest project root in workspaces with multiple roots.

- Use compact +, -, and refresh controls on the right of Kosmo's Git diff toolbar,
  with Auto-refresh beside Refresh at the far right and descriptive tooltips and
  accessibility labels. Leave enough text space for the action symbols to render.

- Keep hosted table controls at their cell size when sibling labels update,
  preventing Inspect buttons and state fields from shrinking until another interaction.

- Add a keymode popup at the bottom right of Kosmo's status bar to switch between
  Moe/Vim modal editing and normal text entry with native editing shortcuts.
  Use a compact menu that opens upward, and keep its checked selection synchronized
  with Settings and detached editor windows.

- Add a Windows VirtualBox test setup, matching Guest Additions, an OpenGL 3.3
  console probe, and guards against concurrent bhyve operation. Document the
  failed GPU acceleration test with the FreeBSD 7.2.20 packages.
- Add a reproducible Windows Server evaluation VM setup for bhyve, with
  unattended installation, private RDP/SSH access, ZFS reset helpers, and GPU
  passthrough configuration and verification instructions.
- Extract table value types, sizing records, and data helpers into
  `nimkit/containers/tablebasics`. Existing TableView and NimKit imports continue
  to expose the public table APIs.
- Group TableView options into an enum set and row selection into a value object,
  preserving existing property setters, selection notifications, and defaults.
- Share typed collection storage, identity indexes, arrangement caching, and
  mutation invalidation between NimKit TableModel and ArrayController. Repeated
  controller lookups now reuse the filtered/sorted arrangement until a model
  mutation; public model APIs, typed edit writeback, and notifications remain
  available. Reassign a filter after changing external state captured by it.
- Maintain shared collection identity indexes during mutations, allocate them
  only for identity queries, and reuse arrangement storage. Cached reads and
  unsorted refreshes avoid comparator closure allocations. Field projections
  borrow values instead of creating temporary ObjectValue copies.
- Keep arranged identity lookups proportional to visible items: defer hidden
  source identities and use generation stamps to discard stale visible positions.

## 0.27.6

- Focus the displayed document when clicking passive areas in a pane's content,
  including GitHub and Git diff readers beside a focused terminal.

- Show project-relative file paths in file-tree hover tooltips, preserving Git
  status details and using the same closest project root as Copy Relative Path.
  Connect outline item tooltips to NimKit's shared hover display.

- Keep editor Find scoped to its pane, including its query, highlights, errors,
  and match navigation when other panes repaint or search the same buffer.
  Closing Find in one pane preserves the other panes' searches. Switching tabs
  rechecks matches without moving the restored cursor.

- End Moe's active Visual selection before GUI Find moves to a match, so copying
  selected text into Find does not select the intervening document text.

- Resolve internal layout anchors after manual containers resize their content,
  keeping nested widgets in the same layout pass without repeated global layout.

- Compose reusable search bars with standard Box and StackView layout. Let hosts
  choose floating or embedded placement, measure expanded and error states from
  their content, and keep floating bars within narrow panes.

- Keep Git diff document navigation out of focused search controls, so Tab and
  arrow keys preserve query focus and caret movement after pasting.

- Keep StackView keyboard traversal aligned with arranged insertion and reordering
  without detaching focused controls.

- Keep pasted text in ordinary text fields at the field's font and color, isolate
  undo history between editing sessions, and use shared text-view mouse selection
  so dragging over text replaces the selected range correctly.

- Add Copy Full Path and Copy Relative Path to Kosmo's file-tree context menu.
  Relative paths use the closest containing project root, including nested roots.

- Let Kosmo's Files/Find sidebar shrink to 128 points, 20% narrower than before.

- Include the visible Files or Find sidebar in Kosmo's Ctrl-W h/l pane focus
  navigation, including Control and arrow aliases. Keep the selected sidebar tab
  and search text, and use Ctrl-W l to return to the adjacent editor or terminal.

- Add "Remove Project Root" to Kosmo's file-tree context menu. Removing a root
  updates the browser, Quick Open, file search, and Git monitoring while keeping
  its files and open tabs.

## 0.27.5

- Start the GitHub viewer with Issues and Pull Requests expanded and individual
  items collapsed. Preserve user expansion choices across refreshes and filters.

- Support Copy and Select All in Kosmo's Markdown, GitHub, Git diff, Help,
  Command Output, and custom document views. Route clipboard shortcuts to the
  focused content, allow Paste in editable views, and keep unsupported edits in
  readers from reaching hidden editor buffers.
- Use installed TextMate grammars, including SQL, for Markdown code fences and
  Git diff highlighting. Resolve installed filename and extension associations,
  load included grammars, and refresh open viewers and cached previews after
  installing a grammar in Settings.

## 0.27.4

- Route Kosmo's copy, cut, paste, select-all, undo, and redo shortcuts to the
  focused search or replacement field. Preserve literal whitespace in search
  queries and replacements when tabbing through controls or expanding Replace.

## 0.27.3

- Keep ordinary clicks between Kosmo editor panes from starting a text
  selection, and align the first visible line after keyboard navigation
  following fractional wheel scrolling.

- Prevent Kosmo editor panes from briefly displaying another buffer when
  switching focus or editing. Pane rendering consumes delivered highlighting
  results without dispatching callbacks that can redraw another pane midway
  through the frame.

- Use Moe's Matter semantic scope mappings to distinguish HTML/custom element
  names, attributes, CSS selectors and common language values in existing themes.
  Preserve preprocessor colors for C/C++ pragmas and string colors for regex
  captures and format placeholders. Adapt Kosmo pane snapshots and Select All to
  Moe's window-owned visual selection API, preserving the cursor and preferred
  column across pane switches.

- Keep the open state during menubar arrow navigation: `<left>`/`<right>` between
  menu bar buttons only move the highlight while the current menu is closed, and
  open the next or previous menu while the current menu is open. Opening menus
  with `<enter>`/`<down>` and tab navigation are unchanged.
- Navigate Kosmo editor split panes with the arrow keys from a focused etab
  strip: `<right>`/`<left>` move to the nearest pane column to the right or
  left (same row preferred, topmost or leftmost pane on ties; a pane spanning
  several rows or columns always targets the topmost or leftmost pane of the
  nearest column) and exit to the next/previous ui element outside the pane at
  the edges, while `<down>`/`<up>` move within a pane column and
  do nothing when there is no vertical neighbor. Arrow keys inside editor text
  keep moving the cursor.
- Keep `<tab>` order after splits following the visual pane layout left to
  right: `SplitView.insertPane` now inserts the pane's view at the matching
  subview position instead of appending it, so the window key view loop (and
  accessibility order) matches the rendered pane order.
- Keep `<tab>` out of Kosmo moe editor panes: from a selected etab it cycles the
  tab selection (`<shift><tab>` backwards) while keeping focus on the strip and
  falls through to the next or previous ui element at the ends, and `<return>`
  enters the editor. In the editor's normal mode `<tab>`/`<shift><tab>` cycle to
  the next/previous ui element, returning to the pane's etab strip. The selected
  etab now highlights only while its pane has keyboard focus, so cycling into
  the menubar or another ui element outside the pane unhighlights it until the
  pane is entered again.

## 0.27.0

- Add GUI resource markup with HTML5 syntax, `nk-` native elements, application
  widget tags, and independent windows inside `nk-main`. Use attributes for typed
  native properties, retain useful HTML control/text shorthands, and validate
  resource IDs, references, load limits, and unsupported syntax. Reuse the existing
  resource model, construction, CBOR serialization, and Tekton preview. Include a
  styled preferences demo using `input`, `span`, and `select`, with compact controls,
  custom/built-in CSS selection, Preview/Reset actions, and a second About window.
  Preserve combo option values, selection, and explicit label overrides during
  resource edits with shared setter ordering and preview replacement when needed.
  Use `nk-view`, `nk-stack-view`, and native `nk-box`/`nk-group` grouping. Box
  resources now own at most one explicit content root; wrap multiple controls in
  a stack. Inherit child hooks/limits and preserve content styling on reattachment.

- Require Matter 0.6.0 or newer and include NIF in Kosmo's built-in language list
  with automatic syntax highlighting for `.nif` files.

- Keep box/group captions readable when switching CSS themes by following the
  active palette's text foreground instead of inheriting Aqua's dark caption color.

- Share immutable theme storage across Theme and Appearance copies, avoiding
  duplicated CSS rule tables and indexes in widget caches. Preserve isolated
  builder edits and mutable copies returned by snapshot accessors.

- Preserve CSS custom-property syntax until use, keeping keywords and units
  consistent with literal declarations and native typed resources. Normalize
  property names before validation, compile shared declarations and diagnostics
  in one pass, and combine repeated bundled CSS blocks. Remove obsolete
  `hasCss`, `cssMetricStates` and `cssMetricsChange` APIs; use `metricStates` and
  `metricsChange` for state-dependent sizing.

- Implement all bundled NimKit themes as embedded CSS with shared widget
  defaults. Unify CSS and programmatic styling precedence, token names and
  state metric invalidation; retain typed ThemeBuilder and Appearance overrides.
  Compile typed declarations once per immutable snapshot and cache bundled
  themes. Support two/three-stop linear gradients and composite variables in
  padding, radii, sizes and shadows. Uniform programmatic radii now replace
  earlier per-corner values consistently.

- Add CSS theming through Stylus 0.1.5 with role/id/class/state selectors,
  declaration-level specificity and importance, typed root variables, explicit
  reloads, and source diagnostics. Style existing control colors, fonts, padding,
  borders, corners, shadows and focus metrics without replacing the native theme;
  CSS metric state changes relayout controls and preserve hover color animation.
  Support edge pins, preferred/percentage dimensions, required min/max bounds and
  scoped sibling/parent/self anchor equations with native solver priorities.
  Expose more control-specific properties and StackView/GridView layout metrics.
  Diagnose container ownership conflicts and invalid runtime targets; retain
  finite geometry and the layout cache on failed solves and fitting measurements.
  Include a stylesheet preview example and CSS theming guide.

- Keep Markdown code block backgrounds visible in Kosmo editor mode while
  asynchronous highlighting catches up with typing, line edits, and undo.
- Highlight and scroll to clicked global file-search matches in Kosmo Markdown
  previews, including results opened while the preview is still loading.

- Share smooth arrow/page keyboard scrolling across NimKit scroll containers
  and read-only text views, including Kosmo Markdown, GitHub and Git diff readers.
  Preserve editable text cursor movement and pass vertical keys through embedded
  horizontal scrollers. Markdown j/k now select visible headings and paragraphs;
  Enter expands or collapses their section and keeps its heading selected.

- Default Kosmo terminals to Hybrid shortcut routing: use Ctrl-W pane chords
  and arrow continuations for splits and navigation, and Ctrl-C/Ctrl-V for
  copy/paste on Linux and Windows. Ctrl-backslash quotes the next shortcut,
  including complete pane chords. Add a persisted Terminal input selector for
  Hybrid or Raw shortcuts, applying changes to current and future terminals.
  Consume printable pane shortcut text before focus changes, so switching from
  an editor or Markdown preview to a terminal does not type the continuation.
  Directional pane shortcuts follow aligned neighboring edges in nested splits.

- Support Reni regular expressions through the `.*` toggle in Kosmo terminal,
  Markdown, GitHub, and Git diff views, the Files filter, Quick Open, and VS Code
  grammar search. Share matching with editor and file search, preserve Unicode
  text and terminal cell positions, and report invalid patterns without stale
  results. Literal viewer matches now follow Reni's nonoverlapping scan.
- Center terminal search matches when history permits, while keeping matches
  near the end of the history at the bottom.
- Expose reusable NimKit `SearchBar` and `TextSearchController` components with
  text-source adapters and optional validated capture replacement hooks.

- Add a searchable GitHub issues and pull requests Markdown tab to Kosmo's File
  menu, backed by `gh` in the selected project repository. Include state and item
  filters, descriptions and metadata, clickable section headings with browser
  links below them, manual refresh, fetch limits, PR job status and details links,
  persistent section expansion across refreshes, optional automatic refresh every
  30 seconds, and cancellable background commands with explicit error messages.

- Reduce Kosmo file-tree indentation to 10 points per level and make it
  configurable with `fileTreeIndentation` in `config.json`.

- Allow `addArrangedSubview` to mix views and `(view, sizingPolicy)` pairs in
  one call.

- Let the todo table example fill the available window space between its input
  and bottom controls.

- Draw checkbox focus rings outside the indicator in every theme, keeping the
  checkmark and checkbox interior clear without increasing layout spacing.

- Let custom layout callbacks assign descendant frames with the ordinary `frame`
  setter without creating layout feedback. Changes outside layout, or to self,
  ancestors, and unrelated views, still invalidate layout normally.

- Stop repeated layout feedback in the draggable todo example by applying
  checkbox frames as container layout output.

- Keep Markdown parsing and streamed syntax highlighting working under `nim ic`
  by using consistent Variant type IDs for threaded worker payloads.

- Preserve Tekton inspector edits under `nim ic`, including string, boolean,
  color, geometry, and invalid text payloads in the resource document.

- Update Moe to `2ad904c1` and bridge its read/write hooks, asynchronous work,
  and targeted buffer deletion into Kosmo. Route hook/build output and `:jobs`
  to a reusable native document, and shell/manual/terminal commands to native
  terminal tabs. Keep background work and visible status updates running when
  Git monitoring is disabled, and cancel/reap hook processes on editor close.
- Keep native Undo/Redo working during ordinary and forced Input transactions.
  Synchronize Vim clipboard registers with the native pasteboard, preserve
  linewise puts, and stop mapping replay after an intercepted native close.
- Make `:wq`, `:x`, and `ZZ` save and close the selected native tab without
  shutting down Moe or rejecting unrelated unsaved tabs. Resolve `:bd` targets
  by stable buffer number or filename and remove their native pane projections.
- Use Moe's undoable reload and post-reload bookkeeping for native workspace
  replacements, including refreshed EditorConfig, LSP, and conflict state.
- Checkpoint unsaved Kosmo buffers into a host-owned recovery store. Show
  preserved work in a native Recovered Work tab with undoable Restore and
  confirmed Discard actions; remove live checkpoints on a clean close.

- Resolve the Git diff panel's key-equivalent selector explicitly so Kosmo builds
  with Nim devel when menu and window procedures use the same name.

- Let standalone Kosmo connect to a TCP LSP endpoint by setting `nimLspCommand`
  to `tcp://host:port`, forwarding framed protocol bytes through its LSP child
  process and closing the connection when the session ends.
- Document Nimdex 0.1.2's `--lsp-listen` setup, default `nim ic` compiler
  requirements, and daemon logging. Initialize LSP with the editor's project
  directory and verify reconnects to a persistent listener with fresh sessions.
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
