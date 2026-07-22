import std/[strutils, unittest]

import figdraw

import merenda/nimkit

import ../../examples/window_effects_demo

suite "NimKit window effects demo":
  test "translucent root does not resolve to the opaque themed background":
    let demo = newWindowEffectsDemo()

    check demo.root.backgroundColor.a > 0.0'f32
    check demo.root.backgroundColor.a < 0.2'f32

    let
      list = buildRenders(demo.root)[DefaultDrawLevel]
      rootNode = list.nodes[list.rootIds[0].int]
    check rootNode.kind == nkRectangle
    check rootNode.fill == fill(demo.root.backgroundColor)

  test "controls update and clear the staged backdrop request":
    let demo = newWindowEffectsDemo()

    check demo.window.backdrop.kind == wbekBlur
    check demo.window.backdrop.regions.len == 0

    demo.effectPicker.selectedIndex = 5
    check demo.effectPicker.sendAction()
    check demo.window.backdrop.kind == wbekMaterial
    check demo.window.backdrop.material == bmSidebar
    check demo.status.text.contains("Material: Sidebar")

    demo.regionToggle.state = bsOn
    check demo.regionToggle.sendAction()
    check demo.window.backdrop.regions.len == 3

    check demo.applyButton.sendAction()
    check demo.window.backdrop.kind == wbekMaterial

    check demo.clearButton.sendAction()
    check demo.window.backdrop.kind == wbekNone
