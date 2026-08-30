# Kosmo keyboard shortcuts

Kosmo combines a native GUI with Moe's Vim-style editor. Its shortcut system
needs to let both styles work without making either surprising:

- A GUI user should get the editing and application shortcuts their platform
  normally uses.
- A Vim user should be able to send the usual control-key commands to Moe.
- Every application shortcut should be visible, configurable, and available
  from a menu when a desktop or window manager owns its key.

This document records the shortcuts Kosmo has today and proposes the profile
and routing system that will make the two styles coexist. Sections labelled
**Proposed** describe a design; they are not configuration options yet.

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
other supported platforms. The current Settings window displays this modifier
as `Cmd` everywhere; it should eventually display the platform-appropriate
name.

`Shortcut` is the conventional application modifier. It is Command on macOS
and Control on Windows and Linux. The current Kosmo bindings unfortunately
use both `Shortcut` and `Command`, which is the central inconsistency the
proposed profiles address.

## Current shortcuts

### Kosmo commands

These are the bindings installed by `initKosmoKeyBindings`. A two-key entry is
a sequence: press and release the first chord, then press the second.

| Shortcut | Action | Notes |
| --- | --- | --- |
| `Command-S` | Save active tab | The File menu also supplies `Shortcut-S`. They are the same on macOS and differ on Windows/Linux. |
| `Ctrl-W Ctrl-W` | Close active tab | Available on every platform. |
| `Command-W` | Close active tab | Added only on macOS. |
| `Command-Q` | Quit Kosmo | The standard application menu also supplies `Shortcut-Q`. |
| `Command-Shift-[` | Previous tab | |
| `Command-Shift-]` | Next tab | |
| `Ctrl-W Ctrl-S` | Split below | Moves/duplicates the active tab into a panel below. |
| `Ctrl-W Ctrl-V` | Split right | Moves/duplicates the active tab into a panel on the right. |
| `Command-Shift-E` | Show and focus Files | |
| `Command-Shift-F` | Show and focus Find in Files | |
| `Shortcut-P` | Quick Open | Command-P on macOS; Control-P elsewhere. |
| `Shortcut-Shift-T` | New terminal tab | Command-Shift-T on macOS; Control-Shift-T elsewhere. |
| `Command-1` through `Command-9` | Focus panel 1 through 9 | Panel 1 is the file browser; editor panels follow. |

Kosmo owns the listed `Ctrl-W` continuations. An unclaimed continuation is
passed on to Moe, so its own Vim-style `Ctrl-W` commands remain possible.

### Menus supplied by the application shell

The standard NimKit menus add the following conventional bindings. Kosmo
replaces the Settings target with its own settings window.

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

The File menu currently adds `Command-O` for Open, `Shortcut-S` for Save,
`Shortcut-P` for Quick Open, and `Shortcut-Shift-T` for New Terminal.

The standard Edit menu is a responder-chain facility. Kosmo does not yet
bridge Moe's visual selection, clipboard operations, undo grouping, and
accessibility selection into those native edit commands. Therefore the Edit
entries are present, but they are not yet a promise of conventional text
editing in a Kosmo editor pane.

### Moe editor input

Outside of a registered Kosmo shortcut, an editor pane forwards the input to
Moe. Its normal Vim-style input therefore remains active, including `v`, `V`,
and `Ctrl-V` for visual selections and Moe's normal-mode `Ctrl` commands.

Kosmo currently has no mode-aware shortcut policy. For example, whether a
physical `Ctrl-V` means Moe's blockwise Visual command or a GUI paste command
depends on which responder handles it, rather than on an explicit user
preference. The proposed system below makes that decision deliberate.

## Current customization

Kosmo loads application shortcut overrides from its configuration directory:

```text
<config-dir>/kosmo/keybindings.json
```

The file is a JSON object whose keys are command names and whose values are a
shortcut string, an array of alternative strings, or `null` to disable the
command. Whitespace separates chords in a sequence.

```json
{
  "kosmo.quickOpen": ["cmd-p", "ctrl-p"],
  "kosmo.nextTab": "ctrl-w ctrl-j",
  "kosmo.previousTab": null
}
```

The current parser accepts `cmd`/`command`, `ctrl`/`control`, `option`/`alt`,
and `shift`. It does not yet accept profile names, `primary`, or `super`.
`cmd` uses the existing `Command` meaning described above.

Only the following command IDs can be overridden today:

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

An override replaces all defaults for that command. Invalid sequences and
unknown command IDs leave the existing command unchanged and are reported in
Kosmo's status area. The Settings window lists the resolved bindings but is
read-only for now.

## Proposed: profiles and input policies

A complete setup has two independent choices:

1. A **shortcut profile** selects the modifiers used for application commands.
2. An **editor input policy** decides whether a conflicting key is handled by
   the GUI or sent to Moe.

Keeping the choices independent lets a Vim user select their preferred
application key layout without giving up Vim input.

### Shortcut profiles

| Profile | Default platform | Primary application modifier | Purpose |
| --- | --- | --- | --- |
| `platform` | Windows and Linux | Control | Conventional desktop application bindings. |
| `macos` | macOS | Command on macOS; Super/Windows on other platforms | A Mac-style application layout. It is selectable on every platform. |
| `vim` | Never automatic | Command on macOS; Super/Windows elsewhere | Keeps physical Control available for Vim-oriented commands; all application bindings remain configurable. |

`macos` is the default profile on macOS. On Linux and Windows, it implements
the requested Command-key layout with the system key: `Command-P` becomes
`Super-P`/`Windows-P`, `Command-S` becomes `Super-S`, and so on. It must never
be the only way to reach an action: a desktop environment or window manager
may reserve a system-key chord before Kosmo sees it.

The profile should define symbolic modifiers rather than make every default
binding choose a physical key:

| Symbolic modifier | `platform` | `macos` and `vim` |
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
| `vim` | Explicit application bindings only | All remaining key input | Users who want terminal-like Vim behavior. |
| `native` | Conventional editing and application bindings in every editor mode | Only unbound input | A forced normal-editor experience. |
| `hybrid` | Conventional editing keys in Insert mode and in mouse-created selections | Vim `Ctrl` input in Normal mode | Users who use both the GUI and Vim modes. |

`hybrid` is the recommended future default for Kosmo. In its normal-editor
contexts, `primary-X/C/V/A/Z`, `primary-Shift-Z` or `primary-Y`, `primary-S`,
`primary-F`, and `primary-W` perform their native actions. In Normal mode,
the physical `Ctrl` chords stay available to Moe, including `Ctrl-W` window
commands. The policy must be visible in Settings and editable per shortcut;
there is no single choice that works for every Vim user.

Native Copy, Cut, Paste, Select All, Undo, and Redo must be semantic editor
operations, not synthetic Moe key presses. In particular, GUI Copy/Cut should
use the active GUI/Moe selection, update the system clipboard and Moe's
registers consistently, and preserve undo transaction boundaries. This
depends on completing the Moe-selection bridge described in the editor work.

### Profile-aware defaults

The eventual defaults should be expressed once in terms of `primary`, with
the physical spelling shown by the active profile:

| Action | Default binding |
| --- | --- |
| Open | `primary-O` |
| Quick Open | `primary-P` |
| Save | `primary-S` |
| Close tab | `primary-W`; retain `Ctrl-W Ctrl-W` in Vim policy |
| Close window | `primary-Shift-W` |
| Quit | `primary-Q` |
| New terminal | `primary-Shift-T` |
| Previous / next tab | `primary-Shift-[` / `primary-Shift-]` |
| Files / Find in Files | `primary-Shift-E` / `primary-Shift-F` |
| Focus panel | `primary-1` through `primary-9` |
| Split below / right | `Ctrl-W Ctrl-S` / `Ctrl-W Ctrl-V` in Vim policy; configurable GUI alternatives otherwise |

This removes the current accidental difference between Save, Quick Open, tab
navigation, and the File menu. It also makes Open, Settings, Close Window,
and the native Edit actions first-class configurable commands rather than
menu-only exceptions.

## Proposed configuration format

The current flat JSON object should continue to load. A future version can
recognize a structured form while treating the existing form as an implicit
`platform`/`vim`-compatible configuration:

```json
{
  "profile": "macos",
  "editorInput": "hybrid",
  "bindings": {
    "kosmo.openFile": "primary-o",
    "kosmo.save": "primary-s",
    "kosmo.closeTab": ["primary-w", "ctrl-w ctrl-w"],
    "kosmo.quickOpen": "primary-p",
    "kosmo.splitHorizontal": "ctrl-w ctrl-s",
    "kosmo.splitVertical": "ctrl-w ctrl-v"
  }
}
```

For a Linux or Windows user who selects `macos`, `primary-o` resolves to
`Super-O`/`Windows-O`; on macOS it resolves to `Command-O`. A user can replace
or disable any such binding with the same string/array/`null` rules used by
the current file.

The resolver should reject duplicate bindings and prefix ambiguities, show the
physical result in Settings and menus, and retain a menu command for every
action. It should also permit a per-mode override such as “use native
`primary-C` in Visual mode, but let Moe handle it in Insert mode.”

## Implementation order

1. Define the action registry for every menu and editor operation, then make
   menus and the Settings table use the same resolved bindings.
2. Add profile-aware symbolic modifiers and a profile selector while preserving
   the current flat JSON format.
3. Bridge Moe's selection, clipboard, undo, and accessibility state to
   NimKit's text-editing commands.
4. Add the `vim`, `native`, and `hybrid` input policies, including mode-aware
   sequence handling for `Ctrl-W`.
5. Test each resolved profile on macOS, Windows, and Linux. In particular,
   verify that system-key bindings fail gracefully when the desktop intercepts
   them.

Avoid using Hyper as a default: many keyboards do not have it. Avoid making
Alt or Control-Alt the primary GUI namespace as well; they collide with menu,
window-manager, and international keyboard behavior. A configurable profile,
menus, and a command palette are more reliable escape hatches than a new
mandatory modifier.
