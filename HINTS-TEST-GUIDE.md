# Kosmo hint mode — manual test guide

This guide walks through the hint-mode feature (Kitty-style screen hints) and
what to expect at each step. It also documents the fixes made after the first
round of testing, so the earlier failures are understandable rather than
surprising.

## Prerequisites

Build Kosmo from the `kosmo-hint-mode` branch:

```sh
cd /home/marcus/projects/buegel/merenda
LC_ALL=C LANG=C nim ic -o:kosmo src/merenda/kosmo/kosmo.nim
```

(An earlier `kosmo` binary built before the fixes below will show exactly the
broken behavior described in "What was wrong in the first test round".)

Open the playground file so it fills the editor:

```sh
./kosmo hints-playground.txt
```

`hints-playground.txt` (next to this guide) contains URLs, real file paths,
line references, words, and hashes to try the commands on.

## Default shortcuts

| Keys | Action |
| --- | --- |
| `F6` | Open Link with Hints (opens the picked URL in your browser) |
| `Shift-F6` | Open File with Hints (opens the picked path in Kosmo, at the hinted line) |
| `Alt-F6` | Copy Word with Hints (copies the picked word to the clipboard) |
| `Ctrl-F6` | Copy Hash with Hints (copies the picked hash) |
| `Ctrl-Shift-F6` | Insert into Terminal with Hints (from a terminal tab, types the picked path into it) |

Every command is rebindable in Kosmo Settings → Shortcuts and in
`~/.config/kosmo/keybindings.json`. On macOS the F-key row may need `fn`, so
the same commands also bind to `Command-Control-E`, `Command-Control-Shift-E`,
`Command-Control-W`, `Command-Control-H`, and `Command-Control-P`.

## How a session behaves

1. Press one of the shortcuts. Green markers with short labels (`1`, `2`, …
   `9`, `a`, … `z`, then `01`, `02`, … for more than 35 matches) appear over
   the matches, and the matches get a soft highlight.
2. Type the label characters of one marker. While a label has more than one
   character, the first character only *filters* the markers — they stay
   visible. Typing the full label picks the snippet.
3. `Escape` cancels. `Backspace` deletes the last typed label character.
   `Enter` confirms when exactly one candidate is left. Clicking a marker
   picks it directly. Any other key (or scrolling, resizing, or switching
   windows) ends the session and gives keyboard focus back to the editor.
4. Keyboard focus always returns to the surface that had it before the
   session started.
5. Markers only cover what is on screen. A command that finds nothing
   visible declines and the status bar at the bottom of the window says so,
   for example `No visible hashes to copy` — scroll the matches into view
   and press the shortcut again.

## Test procedure

### 1. Open a link (F6)

1. Focus the editor tab showing `hints-playground.txt`.
2. Press `F6`.
3. Expect: markers on the `https://…` URLs from section 1 of the playground,
   about nine of them. The glued `xhttps://…` line must NOT get a marker.
   `(see …)` and the trailing comma are handled: the marker text is the clean
   URL.
4. Type the label of `https://example.com/alpha` (the bottom-most URL has the
   shortest label).
5. Expect: your default browser opens that exact URL, markers disappear, and
   focus returns to the editor.

### 2. Open a file, with and without a line (Shift-F6)

1. Press `Shift-F6` in the playground.
2. Expect: markers on the existing paths from sections 2 and 3, including
   `/etc/passwd:10` and the Nim style `/etc/hosts(5, 2)`. `/does/not/exist/…`
   and `and/or` must NOT be hinted.
3. Pick `/etc/passwd:10`.
4. Expect: the file opens in a Kosmo tab and the cursor lands on line 10.
5. Press `Shift-F6` again and pick `/etc/hosts(5, 2)`.
6. Expect: `/etc/hosts` opens with the cursor on line 5.

### 3. Copy a word, including two-character labels (Alt-F6)

1. Press `Alt-F6` in the playground.
2. Expect: markers on every word from section 4 — well over 35, so several
   markers have two-character labels such as `01` or `02`.
3. Type only the first character of a two-character marker.
4. Expect: the session stays alive; the remaining markers start with that
   character. This is the case that was broken in the first test round.
5. Type the second character.
6. Expect: the session ends and the word is in the clipboard — paste it
   anywhere (for example `Ctrl+V` in the editor or in another program).

### 4. Copy a hash (Ctrl-F6)

1. Scroll the editor so the hash section of the playground (section 5, near
   the end of the file) is on screen.
2. Press `Ctrl-F6`.
3. Expect: markers on `deadbeef1234567`, `cafebabe000000`,
   `0123456789abcdef`, and the `4b825dc…` SHA in section 5. The uppercase
   `ABCDEF123456` and the short `123456` must NOT be hinted.
4. Pick one and paste it somewhere to confirm.
5. Scroll back to the top and press `Ctrl-F6` again.
6. Expect: no markers; the status bar says `No visible hashes to copy` —
   hints only collect from the visible area, so the hashes must be on
   screen first.

### 5. Terminal surfaces

1. Open a terminal tab and run the commands from section 6 of the playground
   (the `grep -n root /etc/passwd` one is a good start).
2. Press `F6`, `Shift-F6`, and `Alt-F6` in the terminal.
3. Expect: markers over the visible terminal output only. Picking a URL opens
   the browser; picking a word copies it. If nothing matches — for example
   `F6` on a screen without URLs — the status bar reports the decline.
4. With a path such as `/etc/passwd` visible in the terminal, press
   `Ctrl-Shift-F6` and pick it.
5. Expect: the path is typed into the terminal as if pasted (so you can add
   arguments and press Enter yourself). Pressed while an editor is focused
   instead of a terminal, the command declines with a status-bar message.

### 6. Markdown and diff readers

1. Open any `README.md` (or rename the playground to `.md`) and switch to the
   preview: `Alt-F6` hints the rendered words, `F6` hints rendered links.
2. Open the Git diff tab (`Ctrl-Shift-D`): hints work on the summary and on
   expanded file sections; collapsed sections only hint once expanded and
   scrolled into view.
3. The GitHub issues reader behaves like the Markdown preview.

## What was wrong in the first test round

All five symptoms had three root causes, all now fixed:

- **Nothing activated (URLs did not open, copies could not be pasted) and
  two-character labels died on the first character:** on Linux (and Windows)
  the native backends deliver key events *without* character text — the typed
  character arrives as a separate text commit afterwards. The overlay read the
  character from the key event, found none, and ended the session on every
  keystroke. The overlay now derives the label character from the key itself
  and claims the follow-up text commit so the character is never typed into
  the editor behind the session. Synthetic window tests cannot see this
  because they inject text directly; the fixed tests emulate the empty-text
  events.
- **URLs did not open:** the NimKit workspace's `openUrl` was only implemented
  on macOS; on Linux it reported "unsupported" and did nothing. It now runs
  `xdg-open` (or `gio open`) detached, which also fixes opening links from
  terminal output and the GitHub reader on Linux.
- **Indented paths were not hinted (sections 2 and 3 of the playground):** Moe
  draws indentation guides as a vertical line (`│`) that visually replaces the
  last leading space of an indented line. The glued `│/etc/passwd` matched as
  one "word", so the file check saw `│/etc/passwd` and rejected it — which is
  exactly why a path with text in front of it (like
  `Nim style: /etc/hosts(5, 2)`) still worked. The collector now treats the
  guide as whitespace, so indented paths, line references, and relative paths
  hint like any other.

The tests in `tests/kosmo/hintsmode.nim` cover all three: key events without
text selecting labels, multi-character labels filtering instead of ending the
session, no stray characters reaching the buffer, the workspace advertising
URL opening, and indented paths opening at their hinted line.
