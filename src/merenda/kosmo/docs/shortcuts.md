# Kosmo keyboard shortcuts

Kosmo combines a native GUI with Moe's Vim-style editor. Its shortcut system
needs to let both styles work without making either surprising:

- A GUI user should get the editing and application shortcuts their platform
  normally uses.
- A Vim user should be able to send the usual control-key commands to Moe.
- Every application shortcut should be visible, configurable, and available
  from a menu when a desktop or window manager owns its key.

This document records the implemented shortcut registry, profiles, and input
routing system. It also keeps the reasoning behind the design, so that adding
a command does not reintroduce a conflict between native editing and Moe.

## Terms

Kosmo and NimKit currently distinguish these modifier concepts:

| Name in this document | macOS key | Windows/Linux key | Current NimKit modifier |
| --- | --- | --- | --- |
| `Shortcut` | Command | Control | `shortcutModifiers()` |
| `Command` | Command | Super / Windows (system) | `kmCommand` |
| `Ctrl` | Control | Control | `kmControl` |
| `Alt` | Option | Alt | `kmOption` |

The native backend maps the platform's system modifier to `kmCommand`. Thus a
binding written as `cmd-p` means Command-P on macOS and Super/Windows-P on
other supported platforms. Settings and menus display the resolved physical
modifier for the active profile.

`Shortcut` is the conventional application modifier. It is Command on macOS
and Control on Windows and Linux. Registry defaults use the symbolic
`primary` modifier so profile changes consistently affect every application
action.

## Shortcut registry and defaults

### Kosmo commands

The action registry is the single source for menu actions, the Settings list,
the window key-binding table, and JSON overrides. A two-key entry is a
sequence: press and release the first chord, then press the second. The table
uses `primary`; Settings and menus show its resolved physical spelling.

| Shortcut | Action | Notes |
| --- | --- | --- |
| `primary-O` | Open file | |
| `primary-S` | Save active tab | |
| `primary-W` | Close active tab | `Ctrl-F4` is also available on Windows and Linux. |
| `primary-Shift-W` | Close application window | |
| `primary-Q` | Quit Kosmo | |
| `primary-Shift-[` / `primary-Shift-]` | Previous / next tab | `gT` / `gt` remain Moe tab commands. |
| `primary-Shift-E` / `primary-Shift-F` | Show and focus Files / Find in Files | |
| `primary-P` | Quick Open | |
| `primary-Shift-T` | New terminal tab | |
| `primary-1` through `primary-9` | Focus panel 1 through 9 | Panel 1 is the file browser; editor panels follow. |

The scoped Vim pane commands are described below. They are handled only by a
focused Kosmo editor in the applicable Moe mode; they are not global window
bindings.

### Menus supplied by the application shell

The standard NimKit menus expose the following conventional bindings. Kosmo
routes Settings to its own settings window and routes edit actions through the
semantic editor bridge when a Kosmo editor is focused.

| Shortcut | Menu action |
| --- | --- |
| `Shortcut-,` | Kosmo Settings |
| `Shortcut-H` | Hide Kosmo |
| `Shortcut-Alt-H` | Hide other applications |
| `Shortcut-Q` | Quit |
| `Shortcut-Shift-W` | Close window |
| `Shortcut-Z` / `Shortcut-Shift-Z` | Undo / redo |
| `Shortcut-X`, `Shortcut-C`, `Shortcut-V` | Cut, copy, paste |
| `Shortcut-A` | Select all |

The File menu is populated from the same registry, so Open, Save, Quick Open,
New Terminal, and Close Tab show the resolved key equivalents rather than
separate hard-coded shortcuts.

The standard Edit menu is a responder-chain facility. Kosmo bridges its Copy,
Cut, Paste, Select All, Undo, and Redo commands to semantic Moe operations:
the bridge uses the current selection, synchronizes the system clipboard and
Moe registers, and preserves Moe's undo transactions. It does not emulate
these actions by injecting synthetic keys.

### Moe editor input

Outside of a registered Kosmo shortcut, an editor pane forwards the input to
Moe. Its normal Vim-style input therefore remains active, including `v`, `V`,
and `Ctrl-V` for visual selections and Moe's normal-mode `Ctrl` commands.

Mode-aware routing makes that decision explicit. The selected editor input
policy determines whether a conflicting chord is dispatched to the semantic
native-edit bridge or forwarded to Moe.

## Configuration and Settings

Kosmo loads application shortcut overrides from its configuration directory:

```text
<config-dir>/kosmo/keybindings.json
```

The file accepts either a legacy flat JSON object or a structured object. In
both forms a binding value is a shortcut string, an array of alternative
strings, or `null` to disable the command. Whitespace separates chords in a
sequence.

```json
{
  "kosmo.quickOpen": ["cmd-p", "ctrl-p"],
  "kosmo.nextTab": "ctrl-w ctrl-j",
  "kosmo.previousTab": null
}
```

The parser accepts `cmd`/`command`, `ctrl`/`control`, `option`/`alt`, `shift`,
and `super`, as well as the profile-aware symbolic `primary`, `control`, and
`alternate` spellings. `cmd` retains its existing system-modifier meaning for
backward compatibility.

Every registered Kosmo action can be overridden, including menu actions and
native editing actions. The original command IDs remain valid, including:

```text
kosmo.newTerminal
kosmo.save
kosmo.closeTab
kosmo.quit
kosmo.previousTab
kosmo.nextTab
kosmo.splitHorizontal
kosmo.splitVertical
kosmo.showFileExplorer
kosmo.findInFiles
kosmo.quickOpen
kosmo.focusPanel1 ... kosmo.focusPanel9
```

An override replaces all defaults for that command. Invalid sequences, unknown
command IDs, duplicates, and prefix ambiguities leave the existing command
unchanged and are reported in Kosmo's status area.

The structured form additionally selects the shortcut profile and editor input
policy:

```json
{
  "profile": "macos",
  "editorInput": "hybrid",
  "bindings": {
    "kosmo.openFile": "primary-o",
    "kosmo.save": "primary-s",
    "kosmo.closeTab": "primary-w",
    "kosmo.quickOpen": "primary-p"
  }
}
```

The flat form is interpreted as bindings over the platform's default profile
(`macos` on macOS, `platform` elsewhere) and the `hybrid` input policy.
Existing flat overrides for split commands remain valid. On Linux or Windows,
`primary-o` in the `macos` profile resolves to
`Super-O`/`Windows-O`; on macOS it resolves to `Command-O`.

The Shortcuts page in Kosmo Settings has selectors for **Shortcut profile**
(`platform` or `macos`) and **Editor input** (`hybrid`, `vim`, or `native`),
followed by a read-only list of the resolved action bindings. Changing a
selector applies the choice immediately; the list and menu key equivalents
then show the physical shortcuts for that choice.

## Profiles and input policies

A complete setup has two independent choices:

1. A **shortcut profile** selects the modifiers used for application commands.
2. An **editor input policy** decides whether a conflicting key is handled by
   the GUI or sent to Moe.

Keeping the choices independent lets a Vim user select their preferred
application key layout without giving up Vim input.

### Shortcut profiles

| Profile | Default platform | Primary application modifier | Purpose |
| --- | --- | --- | --- |
| `platform` | Windows and Linux | Command on macOS; Control elsewhere | Conventional application bindings for the host platform. |
| `macos` | macOS | Command on macOS; Super/Windows on other platforms | A Mac-style application layout. It is selectable on every platform. |

`macos` is the default profile on macOS and an explicit opt-in on Linux and
Windows. Outside macOS it provides the same modifier layout using the system
key: `Command-P` becomes `Super-P`/`Windows-P`, `Command-S` becomes `Super-S`,
and so on. This is useful with window managers that leave those chords
available and for users who prefer Command-style copy, paste, save, and other
application shortcuts. It must never be the only way to reach an action: a
desktop environment, window manager, or Windows itself may reserve a system-key
chord before Kosmo sees it.

Vim behavior is an editor input policy, not a shortcut profile. A user can pair
any input policy with either shortcut profile. In particular, a Linux user
can select `macos` for Super-based application commands and `vim` or `hybrid`
for Moe input.

The profile should define symbolic modifiers rather than make every default
binding choose a physical key:

| Symbolic modifier | `platform` | `macos` |
| --- | --- | --- |
| `primary` | Command on macOS; Control elsewhere | Command on macOS; Super/Windows elsewhere |
| `control` | Control | Control |
| `alternate` | Option/Alt | Option/Alt |

The existing `cmd` spelling stays valid for backward compatibility. New
configuration should prefer `primary` for normal application actions and
`control` when it intentionally requires the physical Control key.

### Editor input policies

| Policy | GUI receives | Moe receives | Best for |
| --- | --- | --- | --- |
| `vim` | Explicit, non-conflicting application bindings | All editor input; Kosmo fulfills Moe's pane requests | Users who want terminal-like Vim behavior. |
| `native` | Conventional editing and application bindings in every editor mode | Only unbound input | A forced normal-editor experience. |
| `hybrid` | Conventional primary editing in Insert mode and GUI selection contexts | Normal-mode input and reserved Insert-mode `Ctrl` commands; Kosmo fulfills Moe's pane requests | Users who use both the GUI and Vim modes. |

`hybrid` is the default for Kosmo. In its normal-editor
contexts, `primary-X/C/V/A/Z`, `primary-Shift-Z` or `primary-Y`, `primary-S`,
and the other registered application bindings perform their native actions.
In Normal mode, physical `Ctrl` chords stay available to Moe, including the
`Ctrl-W` pane namespace. The
policy is selected in Settings and can be paired with either profile; there is
no single choice that works for every Vim user.

Hybrid routing is a deliberate per-command matrix rather than a blanket rule
that the GUI owns every key in Insert mode. Routing must consider both the
first responder and Moe's mode. `Ctrl-W` in Moe Normal mode starts a pane
command; in Insert mode it retains Vim's delete-previous-word behavior. A
terminal, sidebar, dialog, or unrelated view must not lose `Ctrl-W` merely
because an editor shortcut uses the same prefix. When the `platform` profile
makes `primary-W` physical Control-W on Windows or Linux, the input policy
resolves the conflict according to that context.

Native Copy, Cut, Paste, Select All, Undo, and Redo are semantic editor
operations, not synthetic Moe key presses. GUI Copy/Cut use the active
GUI/Moe selection, update the system clipboard and Moe's registers
consistently, and preserve undo transaction boundaries.

### Vim pane integration

Kosmo's GUI concepts do not correspond one-to-one with Vim's names:

| Kosmo concept | Closest Vim concept |
| --- | --- |
| Editor panel or split | Window |
| Document tab backed by Moe | Buffer |
| Native application window | No single direct equivalent |

The `Ctrl-W` namespace manages editor panels, not document tabs. Kosmo
supports the Vim spelling with an unmodified second key and, where Vim
supports it, the equivalent control-key spelling:

| Vim input | Kosmo action |
| --- | --- |
| `Ctrl-W s` / `Ctrl-W Ctrl-S` | Split below and show the same buffer. |
| `Ctrl-W v` / `Ctrl-W Ctrl-V` | Split right and show the same buffer. |
| `Ctrl-W n` / `Ctrl-W Ctrl-N` | Create an empty buffer in a new split below. |
| `Ctrl-W w` / `Ctrl-W Ctrl-W` | Focus the next editor panel. This is Vim behavior; it is **not** Close Tab. |
| `Ctrl-W h/j/k/l` | Focus the panel to the left/below/above/right. |
| `Ctrl-W c` | Close the current panel, subject to safe-close checks. |
| `Ctrl-W +`, `-`, `<`, `>`, `=` | Resize or equalize editor panels. |
| `gt` / `gT` | Select the next / previous document tab. |

Kosmo does not assign an established Vim sequence a different meaning. In
particular, closing a document tab remains an application or buffer operation,
rather than a `Ctrl-W` pane operation. Close Tab uses `primary-W`; on Windows
and Linux `Ctrl-F4` is the reliable fallback when the active input policy
reserves physical `Ctrl-W` for Moe.

The current implementation recognizes these commands at the focused Kosmo
editor boundary in the applicable Moe mode, and at a focused Markdown preview.
Markdown previews use the same pane parser and semantic dock operations,
including `Ctrl-W n` to create an empty-buffer split. It deliberately does not
install a window-wide `Ctrl-W` prefix: terminals, sidebars, dialogs, and
unrelated controls keep their own input. Moe receives unclaimed editor input,
so this scoped bridge can later be replaced by a fully configurable Moe
frontend pane-request API without changing Kosmo's panel semantics.

Within a focused Markdown preview, arrow keys scroll smoothly by four lines,
while `j` and `k` retain one-line movement. `Space` scrolls smoothly by one
quarter of the visible preview height.

`Command-W` must remain a complete, immediate close command; it must never be
a sequence prefix. Kosmo should not define `Command-W Command-W`,
`Command-W Command-S`, or similar bindings. GUI-oriented split commands should
instead remain visible in menus and accept independent configurable shortcuts.

### Platform close behavior

Close-tab and close-window commands have distinct defaults. `Ctrl-Shift-W`
must not be repurposed as Close Tab merely because a Vim policy reserves
Control-W:

| Platform and policy | Close document tab | Close application window |
| --- | --- | --- |
| macOS | `Command-W` | `Command-Shift-W` |
| Windows/Linux, `platform` with native routing | `Ctrl-W`; also `Ctrl-F4` | `Ctrl-Shift-W`; also `Alt-F4` |
| Windows/Linux, `platform` with Vim routing in Normal mode | `Ctrl-F4` | `Ctrl-Shift-W`; also `Alt-F4` |
| Windows/Linux, optional `macos` profile | `Super-W`/`Windows-W`; also `Ctrl-F4` | `Super-Shift-W`/`Windows-Shift-W`; also `Alt-F4` |

On Windows, `Ctrl-F4` is a conventional close-document or close-tab command.
It is also common in cross-platform tabbed applications on Linux, making it a
better Vim-policy fallback than changing `Ctrl-Shift-W` to mean Close Tab.
Every close action must remain available from the menu and command palette in
case a system or window manager consumes its key. `Alt-F4` in the table is the
system or window-manager close path; Kosmo need not register a duplicate
binding when the backend already supplies it.

### Profile-aware defaults

The defaults are expressed once in terms of `primary`, with
the physical spelling shown by the active profile:

| Action | Default binding |
| --- | --- |
| Open | `primary-O` |
| Quick Open | `primary-P` |
| Save | `primary-S` |
| Close tab | `primary-W`; also `Ctrl-F4` on Windows/Linux |
| Close window | `primary-Shift-W`; also `Alt-F4` on Windows/Linux |
| Quit | `primary-Q` |
| New terminal | `primary-Shift-T` |
| Previous / next tab | `primary-Shift-[` / `primary-Shift-]`; also `gt` / `gT` through Moe |
| Files / Find in Files | `primary-Shift-E` / `primary-Shift-F` |
| Focus panel | `primary-1` through `primary-9` |
| Split below / right | `Ctrl-W s` / `Ctrl-W v` in Vim routing, with their control-key aliases; configurable GUI alternatives otherwise |

The registry removes the former accidental difference between Save, Quick
Open, tab navigation, and the File menu. It also makes Open, Settings, Close
Window, and the native Edit actions first-class configurable commands rather
than menu-only exceptions.

## Implementation notes

The implementation validates a resolved binding set before installing it:
duplicate bindings and prefix ambiguities are rejected, menus retain a route
to every action, and Settings always shows the final physical spelling. Tests
cover profile resolution, both JSON forms, policy routing, semantic edits, and
the scoped Vim pane namespace. Cross-platform validation should continue to
cover Insert-mode `Ctrl-W`, `Ctrl-F4`, and desktops that reserve a system-key
binding.

Avoid using Hyper as a default: many keyboards do not have it. Avoid making Alt
or Control-Alt the primary GUI namespace as well; they collide with menu,
window-manager, and international keyboard behavior. Super remains deliberate
and optional through the `macos` profile outside macOS, where users can choose
it for a compatible window manager. Configurable profiles, Settings visibility,
and menus are more reliable escape hatches than a new mandatory modifier.
