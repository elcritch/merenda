## Native window geometry stays in logical points on scaled Linux/BSD displays.
import std/[math, unittest]

import figdraw/windowing/siwinshim

import merenda/nimkit

when defined(linux) or defined(bsd):
  proc backingPixels(value, scale: float32): int32 =
    round(value * scale).int32

  suite "NimKit native window scale":
    test "scaled backing sizes preserve logical geometry and size limits":
      block nativeWindowScale:
        let
          app = newApplication("Native Window Scale Test")
          window = newWindow("Scaled Window", frame = rect(80, 80, 240, 140))
          root = newView(frame = rect(0, 0, 240, 140))

        window.contentMinSize = initSize(120, 80)
        window.setContentView(root)
        app.addWindow(window)
        window.makeKeyAndOrderFront()

        try:
          check app.runForFrames(2) == 2
          require window.nativeReady
          let nativeWindow = window.nativeWindowOrNil()
          require not nativeWindow.isNil
          let
            scale = window.nativeContentScale()
            limitScale =
              if nativeWindow.siwinDisplayServerName() == "x11": scale else: 1.0'f32
          check window.frame().size == initSize(240, 140)
          check nativeWindow.size() ==
            ivec2(backingPixels(240, scale), backingPixels(140, scale))
          check nativeWindow.minSize() ==
            ivec2(backingPixels(120, limitScale), backingPixels(80, limitScale))

          window.frame = rect(80, 80, 300, 180)
          discard app.runForFrames(2)
          check window.frame().size == initSize(300, 180)
          check nativeWindow.size() ==
            ivec2(backingPixels(300, scale), backingPixels(180, scale))
        except CatchableError:
          skip()
          break nativeWindowScale
        finally:
          window.close()
