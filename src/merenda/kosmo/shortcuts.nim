## Kosmo action registry, shortcut profiles, and key-binding configuration.

import std/[json, os, strutils]

import ../nimkit as nimkit

const
  KosmoOpenFileAction* = "kosmo.openFile"
  KosmoNewTerminalAction* = "kosmo.newTerminal"
  KosmoSaveAction* = "kosmo.save"
  KosmoCloseTabAction* = "kosmo.closeTab"
  KosmoCloseWindowAction* = "kosmo.closeWindow"
  KosmoQuitAction* = "kosmo.quit"
  KosmoPreviousTabAction* = "kosmo.previousTab"
  KosmoNextTabAction* = "kosmo.nextTab"
  KosmoSplitHorizontalAction* = "kosmo.splitHorizontal"
  KosmoSplitVerticalAction* = "kosmo.splitVertical"
  KosmoShowFileExplorerAction* = "kosmo.showFileExplorer"
  KosmoFindInFilesAction* = "kosmo.findInFiles"
  KosmoQuickOpenAction* = "kosmo.quickOpen"
  KosmoShowSettingsAction* = "kosmo.showSettings"
  KosmoUndoAction* = "kosmo.undo"
  KosmoRedoAction* = "kosmo.redo"
  KosmoCutAction* = "kosmo.cut"
  KosmoCopyAction* = "kosmo.copy"
  KosmoPasteAction* = "kosmo.paste"
  KosmoSelectAllAction* = "kosmo.selectAll"
  KosmoFocusPanelActionPrefix* = "kosmo.focusPanel"
  KosmoMaxFocusPanelShortcut* = 9

type
  KosmoShortcutProfile* {.pure.} = enum
    Platform
    MacOS

  KosmoEditorInputPolicy* {.pure.} = enum
    Vim
    Native
    Hybrid

  KosmoShortcutPlatform* {.pure.} = enum
    MacOS
    Windows
    LinuxBsd

  KosmoActionKind* {.pure.} = enum
    Application
    Editing
    Pane

  KosmoAction* = object
    identifier*: string
    title*: string
    description*: string
    kind*: KosmoActionKind

  KosmoShortcutConfiguration* = object
    profile*: KosmoShortcutProfile
    editorInput*: KosmoEditorInputPolicy
    bindings*: nimkit.KeyBindingTable

  KosmoShortcutLoadResult* = object
    configuration*: KosmoShortcutConfiguration
    applied*: int
    errors*: seq[string]

func currentKosmoShortcutPlatform*(): KosmoShortcutPlatform =
  when defined(macosx) or defined(macos):
    KosmoShortcutPlatform.MacOS
  elif defined(windows):
    KosmoShortcutPlatform.Windows
  else:
    KosmoShortcutPlatform.LinuxBsd

func defaultKosmoShortcutProfile*(): KosmoShortcutProfile =
  if currentKosmoShortcutPlatform() == KosmoShortcutPlatform.MacOS:
    KosmoShortcutProfile.MacOS
  else:
    KosmoShortcutProfile.Platform

func defaultKosmoEditorInputPolicy*(): KosmoEditorInputPolicy =
  KosmoEditorInputPolicy.Hybrid

func identifier*(profile: KosmoShortcutProfile): string =
  case profile
  of KosmoShortcutProfile.Platform: "platform"
  of KosmoShortcutProfile.MacOS: "macos"

func title*(profile: KosmoShortcutProfile): string =
  case profile
  of KosmoShortcutProfile.Platform: "Platform"
  of KosmoShortcutProfile.MacOS: "macOS-style"

func identifier*(policy: KosmoEditorInputPolicy): string =
  case policy
  of KosmoEditorInputPolicy.Vim: "vim"
  of KosmoEditorInputPolicy.Native: "native"
  of KosmoEditorInputPolicy.Hybrid: "hybrid"

func title*(policy: KosmoEditorInputPolicy): string =
  case policy
  of KosmoEditorInputPolicy.Vim: "Vim"
  of KosmoEditorInputPolicy.Native: "Native"
  of KosmoEditorInputPolicy.Hybrid: "Hybrid"

func parseKosmoShortcutProfile*(value: string): KosmoShortcutProfile =
  case value.strip().toLowerAscii()
  of "platform":
    KosmoShortcutProfile.Platform
  of "macos", "mac":
    KosmoShortcutProfile.MacOS
  else:
    raise newException(ValueError, "Unknown shortcut profile '" & value & "'")

func parseKosmoEditorInputPolicy*(value: string): KosmoEditorInputPolicy =
  case value.strip().toLowerAscii()
  of "vim":
    KosmoEditorInputPolicy.Vim
  of "native":
    KosmoEditorInputPolicy.Native
  of "hybrid":
    KosmoEditorInputPolicy.Hybrid
  else:
    raise newException(ValueError, "Unknown editor input policy '" & value & "'")

func focusPanelAction*(panelNumber: int): string =
  ## Return the key-binding command name for a numbered Kosmo panel.
  KosmoFocusPanelActionPrefix & $panelNumber

func kosmoActions*(): seq[KosmoAction] =
  ## Return every configurable action shown by Kosmo's menus and Settings.
  result =
    @[
      KosmoAction(
        identifier: KosmoOpenFileAction,
        title: "Open File",
        description: "Open a file in the active editor panel.",
      ),
      KosmoAction(
        identifier: KosmoQuickOpenAction,
        title: "Quick Open",
        description: "Open a file with Quick Open.",
      ),
      KosmoAction(
        identifier: KosmoNewTerminalAction,
        title: "New Terminal",
        description: "Open a new terminal tab.",
      ),
      KosmoAction(
        identifier: KosmoSaveAction,
        title: "Save",
        description: "Save the active editor tab.",
      ),
      KosmoAction(
        identifier: KosmoCloseTabAction,
        title: "Close Tab",
        description: "Close the active tab.",
      ),
      KosmoAction(
        identifier: KosmoCloseWindowAction,
        title: "Close Window",
        description: "Close the active application window.",
      ),
      KosmoAction(
        identifier: KosmoQuitAction, title: "Quit", description: "Quit Kosmo."
      ),
      KosmoAction(
        identifier: KosmoPreviousTabAction,
        title: "Previous Tab",
        description: "Select the previous tab.",
      ),
      KosmoAction(
        identifier: KosmoNextTabAction,
        title: "Next Tab",
        description: "Select the next tab.",
      ),
      KosmoAction(
        identifier: KosmoSplitHorizontalAction,
        title: "Split Below",
        description: "Split the active editor panel below.",
        kind: KosmoActionKind.Pane,
      ),
      KosmoAction(
        identifier: KosmoSplitVerticalAction,
        title: "Split Right",
        description: "Split the active editor panel on the right.",
        kind: KosmoActionKind.Pane,
      ),
      KosmoAction(
        identifier: KosmoShowFileExplorerAction,
        title: "Files",
        description: "Show and focus the file explorer.",
      ),
      KosmoAction(
        identifier: KosmoFindInFilesAction,
        title: "Find in Files",
        description: "Show and focus Find in Files.",
      ),
      KosmoAction(
        identifier: KosmoShowSettingsAction,
        title: "Settings",
        description: "Show Kosmo Settings.",
      ),
      KosmoAction(
        identifier: KosmoUndoAction,
        title: "Undo",
        description: "Undo the last editor change.",
        kind: KosmoActionKind.Editing,
      ),
      KosmoAction(
        identifier: KosmoRedoAction,
        title: "Redo",
        description: "Redo the last undone editor change.",
        kind: KosmoActionKind.Editing,
      ),
      KosmoAction(
        identifier: KosmoCutAction,
        title: "Cut",
        description: "Cut the editor selection.",
        kind: KosmoActionKind.Editing,
      ),
      KosmoAction(
        identifier: KosmoCopyAction,
        title: "Copy",
        description: "Copy the editor selection.",
        kind: KosmoActionKind.Editing,
      ),
      KosmoAction(
        identifier: KosmoPasteAction,
        title: "Paste",
        description: "Paste into the editor.",
        kind: KosmoActionKind.Editing,
      ),
      KosmoAction(
        identifier: KosmoSelectAllAction,
        title: "Select All",
        description: "Select all editor text.",
        kind: KosmoActionKind.Editing,
      ),
    ]
  for panelNumber in 1 .. KosmoMaxFocusPanelShortcut:
    result.add KosmoAction(
      identifier: panelNumber.focusPanelAction(),
      title: "Focus Panel " & $panelNumber,
      description: "Focus panel " & $panelNumber & ".",
    )

func kosmoShortcutCommands*(): seq[string] =
  for action in kosmoActions():
    result.add action.identifier

func kosmoAction*(identifier: string): KosmoAction =
  for action in kosmoActions():
    if action.identifier == identifier:
      return action
  KosmoAction(
    identifier: identifier, title: identifier, description: "Run this command."
  )

func primaryModifiers*(
    profile: KosmoShortcutProfile, platform = currentKosmoShortcutPlatform()
): set[nimkit.KeyModifier] =
  if platform == KosmoShortcutPlatform.MacOS or profile == KosmoShortcutProfile.MacOS:
    {nimkit.kmCommand}
  else:
    {nimkit.kmControl}

func symbolicModifier(
    name: string, profile: KosmoShortcutProfile, platform: KosmoShortcutPlatform
): string =
  case name
  of "primary":
    if nimkit.kmCommand in profile.primaryModifiers(platform): "cmd" else: "ctrl"
  of "control":
    "ctrl"
  of "alternate":
    "alt"
  of "super":
    "cmd"
  else:
    name

func resolveSymbolicStroke(
    description: string, profile: KosmoShortcutProfile, platform: KosmoShortcutPlatform
): string =
  let parts = description.split('-')
  for index, part in parts:
    if index > 0:
      result.add '-'
    if index < parts.high:
      result.add part.symbolicModifier(profile, platform)
    else:
      result.add part

func resolveSymbolicShortcut*(
    description: string,
    profile: KosmoShortcutProfile,
    platform = currentKosmoShortcutPlatform(),
): string =
  let strokes = description.splitWhitespace()
  for index, strokeDescription in strokes:
    if index > 0:
      result.add ' '
    result.add strokeDescription.resolveSymbolicStroke(profile, platform)

proc parseKosmoKeySequence*(
    description: string,
    profile: KosmoShortcutProfile,
    platform = currentKosmoShortcutPlatform(),
): nimkit.KeySequence =
  nimkit.parseKeySequence(description.resolveSymbolicShortcut(profile, platform))

proc addBinding(
    table: var nimkit.KeyBindingTable,
    description, action: string,
    profile: KosmoShortcutProfile,
    platform: KosmoShortcutPlatform,
) =
  table.add(
    description.parseKosmoKeySequence(profile, platform), nimkit.actionSelector(action)
  )

proc initKosmoKeyBindings*(
    profile: KosmoShortcutProfile, platform = currentKosmoShortcutPlatform()
): nimkit.KeyBindingTable =
  ## Return the resolved defaults for `profile` on `platform`.
  result.addBinding("primary-o", KosmoOpenFileAction, profile, platform)
  result.addBinding("primary-p", KosmoQuickOpenAction, profile, platform)
  result.addBinding("primary-shift-t", KosmoNewTerminalAction, profile, platform)
  result.addBinding("primary-s", KosmoSaveAction, profile, platform)
  result.addBinding("primary-w", KosmoCloseTabAction, profile, platform)
  if platform != KosmoShortcutPlatform.MacOS:
    result.addBinding("ctrl-f4", KosmoCloseTabAction, profile, platform)
  result.addBinding("primary-shift-w", KosmoCloseWindowAction, profile, platform)
  result.addBinding("primary-q", KosmoQuitAction, profile, platform)
  result.addBinding("primary-shift-[", KosmoPreviousTabAction, profile, platform)
  result.addBinding("primary-shift-]", KosmoNextTabAction, profile, platform)
  result.addBinding("primary-shift-e", KosmoShowFileExplorerAction, profile, platform)
  result.addBinding("primary-shift-f", KosmoFindInFilesAction, profile, platform)
  result.addBinding("primary-,", KosmoShowSettingsAction, profile, platform)
  result.addBinding("primary-z", KosmoUndoAction, profile, platform)
  result.addBinding("primary-shift-z", KosmoRedoAction, profile, platform)
  if platform != KosmoShortcutPlatform.MacOS:
    result.addBinding("primary-y", KosmoRedoAction, profile, platform)
  result.addBinding("primary-x", KosmoCutAction, profile, platform)
  result.addBinding("primary-c", KosmoCopyAction, profile, platform)
  result.addBinding("primary-v", KosmoPasteAction, profile, platform)
  result.addBinding("primary-a", KosmoSelectAllAction, profile, platform)
  for panelNumber in 1 .. KosmoMaxFocusPanelShortcut:
    result.addBinding(
      "primary-" & $panelNumber, panelNumber.focusPanelAction(), profile, platform
    )

proc initKosmoShortcutConfiguration*(
    profile = defaultKosmoShortcutProfile(),
    editorInput = defaultKosmoEditorInputPolicy(),
    platform = currentKosmoShortcutPlatform(),
): KosmoShortcutConfiguration =
  KosmoShortcutConfiguration(
    profile: profile,
    editorInput: editorInput,
    bindings: initKosmoKeyBindings(profile, platform),
  )

func initKosmoKeyBindings*(): nimkit.KeyBindingTable =
  ## Return Kosmo's platform-specific shortcut defaults.
  initKosmoKeyBindings(defaultKosmoShortcutProfile())

func defaultKosmoKeyBindingsPath*(): string =
  ## Return the standalone editor's user key bindings file path.
  getConfigDir() / "kosmo" / "keybindings.json"

func equivalent(left, right: nimkit.KeyStroke): bool =
  if left.modifiers != right.modifiers:
    return false
  if left.key != nimkit.keyUnknown and right.key != nimkit.keyUnknown:
    return left.key == right.key
  if left.keyCode != 0 and right.keyCode != 0:
    return left.keyCode == right.keyCode
  left.text.len > 0 and right.text.len > 0 and
    left.text.toLowerAscii() == right.text.toLowerAscii()

func isPrefix(left, right: nimkit.KeySequence): bool =
  if left.strokes.len > right.strokes.len:
    return false
  for index, stroke in left.strokes:
    if not stroke.equivalent(right.strokes[index]):
      return false
  true

proc addUnique(
    table: var nimkit.KeyBindingTable,
    sequence: nimkit.KeySequence,
    selector: nimkit.CommandSelector,
) =
  for binding in table.bindings:
    if sequence.isPrefix(binding.sequence) or binding.sequence.isPrefix(sequence):
      let relation =
        if sequence.strokes.len == binding.sequence.strokes.len:
          "duplicates"
        else:
          "conflicts with the prefix of"
      raise newException(
        ValueError, "Shortcut " & relation & " '" & $binding.selector.name & "'"
      )
  table.add(sequence, selector)

func shortcutDescriptions(
    command: string, value: JsonNode, descriptions: var seq[string]
): string =
  case value.kind
  of JString:
    descriptions.add value.getStr()
  of JArray:
    for item in value.items:
      if item.kind != JString:
        return "Key binding '" & command & "' must contain only strings"
      descriptions.add item.getStr()
  of JNull:
    discard
  else:
    return "Key binding '" & command & "' must be a string, array, or null"

proc applyKosmoBindingOverrides(
    configuration: var KosmoShortcutConfiguration,
    node: JsonNode,
    platform: KosmoShortcutPlatform,
): nimkit.KeyBindingJsonResult =
  if node.kind != JObject:
    result.errors.add "Key bindings JSON must be an object"
    return
  let allowed = kosmoShortcutCommands()
  for command, value in node.pairs:
    if command.len == 0:
      result.errors.add "Key binding command names cannot be empty"
    elif command notin allowed:
      result.errors.add "Unknown key binding command '" & command & "'"
    else:
      var descriptions: seq[string]
      let descriptionError = command.shortcutDescriptions(value, descriptions)
      if descriptionError.len > 0:
        result.errors.add descriptionError
        continue
      var sequences: seq[nimkit.KeySequence]
      try:
        for description in descriptions:
          sequences.add description.parseKosmoKeySequence(
            configuration.profile, platform
          )
      except ValueError as error:
        result.errors.add "Invalid shortcut for '" & command & "': " & error.msg
        continue
      let selector = nimkit.actionSelector(command)
      var updated: nimkit.KeyBindingTable
      try:
        for binding in configuration.bindings.bindings:
          if binding.selector != selector:
            updated.addUnique(binding.sequence, binding.selector)
        for sequence in sequences:
          updated.addUnique(sequence, selector)
        configuration.bindings = move updated
        inc result.applied
      except ValueError as error:
        result.errors.add "Invalid shortcut for '" & command & "': " & error.msg

proc applyKosmoShortcutConfiguration*(
    node: JsonNode,
    base = initKosmoShortcutConfiguration(),
    platform = currentKosmoShortcutPlatform(),
): KosmoShortcutLoadResult =
  ## Apply structured or legacy flat JSON without partially applying bad fields.
  result.configuration = base
  if node.kind != JObject:
    result.errors.add "Kosmo shortcut configuration must be an object"
    return

  let structured =
    node.hasKey("profile") or node.hasKey("editorInput") or node.hasKey("bindings")
  if structured:
    var profile = base.profile
    var editorInput = base.editorInput
    if node.hasKey("profile"):
      if node["profile"].kind != JString:
        result.errors.add "Shortcut profile must be a string"
      else:
        try:
          profile = parseKosmoShortcutProfile(node["profile"].getStr())
        except ValueError as error:
          result.errors.add error.msg
    if node.hasKey("editorInput"):
      if node["editorInput"].kind != JString:
        result.errors.add "Editor input policy must be a string"
      else:
        try:
          editorInput = parseKosmoEditorInputPolicy(node["editorInput"].getStr())
        except ValueError as error:
          result.errors.add error.msg
    if result.errors.len > 0:
      return
    result.configuration =
      initKosmoShortcutConfiguration(profile, editorInput, platform)
    if node.hasKey("bindings"):
      let bindingResult =
        result.configuration.applyKosmoBindingOverrides(node["bindings"], platform)
      result.applied = bindingResult.applied
      result.errors.add bindingResult.errors
    for key, _ in node.pairs:
      if key notin ["profile", "editorInput", "bindings"]:
        result.errors.add "Unknown shortcut configuration field '" & key & "'"
  else:
    let bindingResult = result.configuration.applyKosmoBindingOverrides(node, platform)
    result.applied = bindingResult.applied
    result.errors.add bindingResult.errors

proc applyKosmoShortcutConfigurationJson*(
    jsonText: string,
    base = initKosmoShortcutConfiguration(),
    platform = currentKosmoShortcutPlatform(),
): KosmoShortcutLoadResult =
  try:
    result = applyKosmoShortcutConfiguration(parseJson(jsonText), base, platform)
  except JsonParsingError as error:
    result.configuration = base
    result.errors.add "Invalid shortcut configuration JSON: " & error.msg

proc loadKosmoShortcutConfiguration*(
    path: string,
    base = initKosmoShortcutConfiguration(),
    platform = currentKosmoShortcutPlatform(),
): KosmoShortcutLoadResult =
  try:
    result = applyKosmoShortcutConfigurationJson(readFile(path), base, platform)
  except IOError as error:
    result.configuration = base
    result.errors.add "Could not read key bindings from '" & path & "': " & error.msg
