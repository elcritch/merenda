import std/unittest

import merenda/nimkit
import merenda/kosmo/shortcuts

proc keyEvent(key: Key, modifiers: set[KeyModifier]): KeyEvent =
  KeyEvent(key: key, keyCode: key.ord, modifiers: modifiers)

proc bindingFor(
    bindings: KeyBindingTable, events: openArray[KeyEvent]
): CommandSelector =
  let matched = bindings.match(events)
  if matched.kind == kbmCommand:
    result = matched.selector

suite "Kosmo shortcut profiles":
  test "platform and macOS profiles resolve primary on every platform":
    for platform in KosmoShortcutPlatform:
      let platformBindings =
        initKosmoKeyBindings(KosmoShortcutProfile.Platform, platform)
      let macosBindings = initKosmoKeyBindings(KosmoShortcutProfile.MacOS, platform)
      let expectedPlatformModifiers =
        if platform == KosmoShortcutPlatform.MacOS:
          {kmCommand}
        else:
          {kmControl}

      check platformBindings.bindingFor([keyEvent(keyS, expectedPlatformModifiers)]) ==
        actionSelector(KosmoSaveAction)
      check platformBindings.bindingFor([keyEvent(keyN, expectedPlatformModifiers)]) ==
        actionSelector(KosmoNewFileAction)
      check platformBindings.bindingFor(
        [keyEvent(keyO, expectedPlatformModifiers + {kmShift})]
      ) == actionSelector(KosmoOpenProjectAction)
      check macosBindings.bindingFor([keyEvent(keyS, {kmCommand})]) ==
        actionSelector(KosmoSaveAction)
      if platform != KosmoShortcutPlatform.MacOS:
        check platformBindings.bindingFor([keyEvent(keyF4, {kmControl})]) ==
          actionSelector(KosmoCloseTabAction)
        check macosBindings.bindingFor([keyEvent(keyF4, {kmControl})]) ==
          actionSelector(KosmoCloseTabAction)
        check macosBindings.bindingFor([keyEvent(keyS, {kmControl})]) ==
          CommandSelector()

  test "defaults leave control-W sequences to Vim pane commands":
    for profile in KosmoShortcutProfile:
      for platform in KosmoShortcutPlatform:
        let bindings = initKosmoKeyBindings(profile, platform)
        let controlW = keyEvent(keyW, {kmControl})
        check bindings.match([controlW]).kind != kbmPrefix
        check bindings.match([controlW, controlW]).kind == kbmNone
        check bindings.match([controlW, keyEvent(keyS, {kmControl})]).kind == kbmNone
        check bindings.match([controlW, keyEvent(keyV, {kmControl})]).kind == kbmNone

  test "numbered panel shortcuts stop at eight":
    let bindings =
      initKosmoKeyBindings(KosmoShortcutProfile.MacOS, KosmoShortcutPlatform.LinuxBsd)

    check bindings.bindingFor([keyEvent(key1, {kmCommand})]) ==
      actionSelector(1.focusPanelAction())
    check bindings.bindingFor([keyEvent(key8, {kmCommand})]) ==
      actionSelector(8.focusPanelAction())
    check bindings.match([keyEvent(key9, {kmCommand})]).kind == kbmNone

  test "structured configuration resolves profile, editor mode, and symbolic bindings":
    let loaded = applyKosmoShortcutConfigurationJson(
      """{
        "profile": "macos",
        "editorInput": "vim",
        "bindings": {
          "kosmo.save": "primary-shift-s",
          "kosmo.quickOpen": "super-p",
          "kosmo.copy": "alternate-c"
        }
      }""",
      platform = KosmoShortcutPlatform.Windows,
    )

    check loaded.errors.len == 0
    check loaded.applied == 3
    check loaded.configuration.profile == KosmoShortcutProfile.MacOS
    check loaded.configuration.editorInput == KosmoEditorInputPolicy.Vim
    check loaded.configuration.bindings.bindingFor(
      [keyEvent(keyS, {kmCommand, kmShift})]
    ) == actionSelector(KosmoSaveAction)
    check loaded.configuration.bindings.bindingFor([keyEvent(keyP, {kmCommand})]) ==
      actionSelector(KosmoQuickOpenAction)
    check loaded.configuration.bindings.bindingFor([keyEvent(keyC, {kmOption})]) ==
      actionSelector(KosmoCopyAction)

  test "legacy flat binding JSON retains the supplied configuration mode":
    let base = initKosmoShortcutConfiguration(
      KosmoShortcutProfile.Platform, KosmoEditorInputPolicy.Native,
      KosmoShortcutPlatform.LinuxBsd,
    )
    let loaded = applyKosmoShortcutConfigurationJson(
      """{"kosmo.save": "ctrl-shift-s"}""", base, KosmoShortcutPlatform.LinuxBsd
    )

    check loaded.errors.len == 0
    check loaded.applied == 1
    check loaded.configuration.profile == KosmoShortcutProfile.Platform
    check loaded.configuration.editorInput == KosmoEditorInputPolicy.Native
    check loaded.configuration.bindings.bindingFor(
      [keyEvent(keyS, {kmControl, kmShift})]
    ) == actionSelector(KosmoSaveAction)

  test "duplicate bindings are rejected without replacing the first action":
    let loaded = applyKosmoShortcutConfigurationJson(
      """{
        "bindings": {
          "kosmo.save": "ctrl-k",
          "kosmo.openFile": "ctrl-k"
        }
      }""",
      platform = KosmoShortcutPlatform.LinuxBsd,
    )

    check loaded.applied == 1
    check loaded.errors.len == 1
    check loaded.configuration.bindings.bindingFor([keyEvent(keyK, {kmControl})]) ==
      actionSelector(KosmoSaveAction)

  test "prefix-ambiguous bindings are rejected":
    let loaded = applyKosmoShortcutConfigurationJson(
      """{
        "bindings": {
          "kosmo.save": "ctrl-k",
          "kosmo.openFile": "ctrl-k ctrl-o"
        }
      }""",
      platform = KosmoShortcutPlatform.LinuxBsd,
    )

    check loaded.applied == 1
    check loaded.errors.len == 1
    check loaded.configuration.bindings.bindingFor([keyEvent(keyK, {kmControl})]) ==
      actionSelector(KosmoSaveAction)
    check loaded.configuration.bindings.bindingFor(
      [keyEvent(keyK, {kmControl}), keyEvent(keyO, {kmControl})]
    ) == CommandSelector()
