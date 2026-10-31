import std/[options, os, unittest]

import figdraw/windowing/siwinshim as figdrawSiwin
import merenda/nimkit/app/backend as nimkitBackend
import merenda/nimkit/foundation/events

when defined(merenda.softwareRenderer) or (
  defined(windows) and (
    defined(merendaTestGpuFailure) or defined(figdrawTestVulkanInitFailure) or
    defined(merendaTestVulkanBackend)
  )
):
  import std/[monotimes, times]
  import figdraw
  import merenda/nimkit/foundation/types as nimkitTypes

type EnvSnapshot = object
  name: string
  existed: bool
  value: string

proc withCleanUiScaleEnv(body: proc() {.closure.}) =
  var snapshot: seq[EnvSnapshot]
  for name in nimkitBackend.UiScaleEnvVars:
    snapshot.add EnvSnapshot(name: name, existed: existsEnv(name), value: getEnv(name))
    delEnv(name)

  try:
    body()
  finally:
    for item in snapshot:
      if item.existed:
        putEnv(item.name, item.value)
      else:
        delEnv(item.name)

suite "nimkit backend":
  when defined(merenda.softwareRenderer) or
      (defined(windows) and defined(merendaTestGpuFailure)):
    test "software renderer presents a native window frame":
      var host: nimkitBackend.HostWindow
      var screenshot: Image
      var renders = newRenders()
      discard renders.addRoot(
        Fig(
          kind: nkRectangle,
          screenBox: figdraw.rect(0, 0, 20, 20),
          fill: rgba(255, 0, 0, 255),
        )
      )
      let callbacks = nimkitBackend.HostWindowCallbacks(
        onRender: proc() =
          if not host.isNil:
            when defined(windows):
              echo "Windows software test: rendering frame"
            host.render(renders, nimkitTypes.initSize(80, 60))
            if host.renderCount() > 0:
              screenshot = host.rendererOrNil().takeOneFrameScreenshot()
      )
      host = nimkitBackend.createHostWindow(
        nimkitTypes.rect(20, 20, 80, 60),
        "Software renderer test",
        callbacks,
        uiScaleOverride = some(1.25'f32),
      )
      defer:
        host.close()
      when defined(windows):
        echo "Windows software test: host created"
      check host.rendererOrNil().backendKind() == rbSoftware
      when defined(merenda.softwareRenderer):
        check not nimkitBackend.dedicatedRendererSupported()
      host.requestRender()
      let deadline = getMonoTime() + initDuration(seconds = 60)
      while screenshot.isNil and getMonoTime() < deadline:
        discard nimkitBackend.pollNativeEvents()
        host.pump()
        sleep(5)
      require not screenshot.isNil
      check screenshot.width > 0 and screenshot.height > 0
      let pixel = screenshot[5, 5]
      check pixel.r > 200 and pixel.g < 30 and pixel.b < 30 and pixel.a == 255

  when defined(windows) and defined(figdrawTestVulkanInitFailure) and
      not defined(merendaTestGpuFailure):
    test "Windows Vulkan initialization failure falls back to OpenGL":
      let host = nimkitBackend.createHostWindow(
        nimkitTypes.rect(20, 20, 80, 60),
        "Vulkan fallback test",
        nimkitBackend.HostWindowCallbacks(),
      )
      defer:
        host.close()
      echo "Windows OpenGL test: host created"
      check host.rendererOrNil().backendKind() == rbOpenGL

  when defined(windows) and defined(merendaTestVulkanBackend):
    test "Windows Vulkan presents frames on the dedicated renderer":
      var runtime = nimkitBackend.newThreadRendererRuntime()
      let host = nimkitBackend.createHostWindow(
        nimkitTypes.rect(20, 20, 80, 60),
        "Vulkan presentation test",
        nimkitBackend.HostWindowCallbacks(),
      )
      defer:
        runtime.stop()
        runtime.join()
        host.close()
      require host.rendererOrNil().backendKind() == rbVulkan
      runtime.start()
      let deadline = getMonoTime() + initDuration(seconds = 60)
      while not runtime.client.isRunning() and getMonoTime() < deadline:
        discard nimkitBackend.pollNativeEvents()
        sleep(5)
      require runtime.client.isRunning()
      let client =
        host.attachThreadRenderer(runtime.client, nimkitTypes.initSize(80, 60))
      require not client.isNil
      require client.submitRenders(newRenders(), nimkitTypes.initSize(80, 60))
      var rendered = false
      while not rendered and getMonoTime() < deadline:
        discard nimkitBackend.pollNativeEvents()
        host.pump()
        var event: nimkitBackend.ThreadHostEvent
        while client.pollEvent(event):
          if event.kind == nimkitBackend.theRendered:
            rendered = true
        sleep(5)
      check rendered

  test "layer surface APIs are limited to Wayland platforms":
    when defined(linux) or defined(bsd):
      check declared(nimkitBackend.LayerSurfaceConfig)
      check declared(nimkitBackend.createLayerSurfaceHostWindow)
    else:
      check not declared(nimkitBackend.LayerSurfaceConfig)
      check not declared(nimkitBackend.createLayerSurfaceHostWindow)

  test "native modifier flags preserve held modifiers without cached key presses":
    check nimkitBackend.toNimkitModifiers(
      {
        figdrawSiwin.ModifierKey.shift, figdrawSiwin.ModifierKey.control,
        figdrawSiwin.ModifierKey.alt, figdrawSiwin.ModifierKey.system,
      }
    ) == {kmShift, kmControl, kmOption, kmCommand}

  when defined(macosx):
    test "macOS screenshot capture cannot leave cached modifier keys active":
      for key in [
        figdrawSiwin.Key.lshift, figdrawSiwin.Key.rshift, figdrawSiwin.Key.lcontrol,
        figdrawSiwin.Key.rcontrol, figdrawSiwin.Key.lalt, figdrawSiwin.Key.ralt,
        figdrawSiwin.Key.lsystem, figdrawSiwin.Key.rsystem,
      ]:
        check nimkitBackend.toNimkitModifiers({}, {key}) == {}

      check nimkitBackend.toNimkitModifiers(
        {figdrawSiwin.ModifierKey.control},
        {figdrawSiwin.Key.lshift, figdrawSiwin.Key.lsystem},
      ) == {kmControl}
  else:
    test "held native modifier keys supplement missing event modifier flags":
      check nimkitBackend.toNimkitModifiers({}, {figdrawSiwin.Key.lsystem}) ==
        {kmCommand}
      check nimkitBackend.toNimkitModifiers(
        {}, {figdrawSiwin.Key.rcontrol, figdrawSiwin.Key.lshift}
      ) == {kmControl, kmShift}
      check nimkitBackend.toNimkitModifiers({figdrawSiwin.ModifierKey.alt}, {}) ==
        {kmOption}

  test "native text input ignores control keys handled by physical key events":
    for text in ["", "\b", "\t", "\n", "\r", "\x7f"]:
      check not nimkitBackend.isNativeTextInput(text)
    for text in ["x", "λ", "hello", "hello\nworld"]:
      check nimkitBackend.isNativeTextInput(text)

  test "ui scale override prefers NimKit env over aliases":
    withCleanUiScaleEnv(
      proc() =
        putEnv(nimkitBackend.NimKitUiScaleEnv, "1.25")
        putEnv(nimkitBackend.NimKitCompactUiScaleEnv, "1.35")
        putEnv(nimkitBackend.MerendaUiScaleEnv, "1.5")
        putEnv(nimkitBackend.UiScaleEnv, "1.75")
        putEnv(nimkitBackend.FigDrawLegacyUiScaleEnv, "2.0")

        let override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        when defined(nimkitIgnoreEnvOverrides):
          check override.get().envName == nimkitBackend.MerendaUiScaleEnv
          check abs(override.get().scale - 1.5'f32) < 0.0001'f32
        else:
          check override.get().envName == nimkitBackend.NimKitUiScaleEnv
          check abs(override.get().scale - 1.25'f32) < 0.0001'f32
    )

  test "ui scale override falls back through Merenda, UISCALE, and legacy env vars":
    withCleanUiScaleEnv(
      proc() =
        putEnv(nimkitBackend.MerendaUiScaleEnv, "1.5")
        putEnv(nimkitBackend.UiScaleEnv, "1.75")
        putEnv(nimkitBackend.FigDrawLegacyUiScaleEnv, "2.0")

        var override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        check override.get().envName == nimkitBackend.MerendaUiScaleEnv
        check abs(override.get().scale - 1.5'f32) < 0.0001'f32

        delEnv(nimkitBackend.MerendaUiScaleEnv)
        override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        check override.get().envName == nimkitBackend.UiScaleEnv
        check abs(override.get().scale - 1.75'f32) < 0.0001'f32

        delEnv(nimkitBackend.UiScaleEnv)
        override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        check override.get().envName == nimkitBackend.FigDrawLegacyUiScaleEnv
        check abs(override.get().scale - 2.0'f32) < 0.0001'f32
    )

  test "ui scale override ignores empty values and rejects non-positive values":
    withCleanUiScaleEnv(
      proc() =
        putEnv(nimkitBackend.NimKitUiScaleEnv, " ")
        putEnv(nimkitBackend.MerendaUiScaleEnv, "1.75")

        var override = nimkitBackend.uiScaleOverrideFromEnv()
        check override.isSome
        check override.get().envName == nimkitBackend.MerendaUiScaleEnv
        check abs(override.get().scale - 1.75'f32) < 0.0001'f32

        putEnv(nimkitBackend.NimKitUiScaleEnv, "0")
        when defined(nimkitIgnoreEnvOverrides):
          override = nimkitBackend.uiScaleOverrideFromEnv()
          check override.isSome
          check override.get().envName == nimkitBackend.MerendaUiScaleEnv
          check abs(override.get().scale - 1.75'f32) < 0.0001'f32
        else:
          expect ValueError:
            discard nimkitBackend.uiScaleOverrideFromEnv()
    )
