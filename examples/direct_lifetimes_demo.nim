## Explicit controller visibility policy; document work need not share this lifetime.
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/directviews

type LifetimeController* = ref object of ViewController
  count*: Sigil[int]
  content*: DirectView

proc pauseContent(controller: LifetimeController) {.slot.} =
  controller.content.suspendUpdates()

proc resumeContent(controller: LifetimeController) {.slot.} =
  controller.content.resumeUpdates()

proc newLifetimeController*(): LifetimeController =
  result = LifetimeController(count: newSigil(0), content: newDirectView())
  result.initViewController()
  result.view = result.content
  let source = result.count
  result.content.viewBody:
    Label:
      this.identifier = "observed-count"
      bindValue(id = "count", input = source) do(label: Label, value: int):
        label.stringValue = "Latest count: " & $value
  result.connect(didDisappear, result, pauseContent)
  result.connect(willAppear, result, resumeContent)
  result.viewWillAppear()
  result.viewDidAppear()

proc showContent*(controller: LifetimeController, visible: bool) =
  if visible:
    controller.viewWillAppear()
    controller.content.hidden = false
    controller.viewDidAppear()
  else:
    controller.viewWillDisappear()
    controller.content.hidden = true
    controller.viewDidDisappear()

proc runDirectLifetimes*() =
  let controller = newLifetimeController()
  let toolbar = newDirectView()
  toolbar.viewBody:
    HStack:
      Button("Increment"):
        onAction(controller) do(this: Button, owner: LifetimeController):
          owner.count <- owner.count{} + 1
      Button("Hide and suspend"):
        onAction(controller) do(this: Button, owner: LifetimeController):
          owner.showContent(false)
      Button("Show and resume"):
        onAction(controller) do(this: Button, owner: LifetimeController):
          owner.showContent(true)
  let root = newStackView(laVertical)
  root.edgeInsets = insets(12)
  root.spacing = 12
  root.addArrangedSubview(
    newLabel("Hide, increment several times, then show the latest count."),
    toolbar,
    controller.content,
  )
  sharedApplication().runWindow(
    newWindow("DirectView lifetime", frame = rect(80, 80, 600, 200)), root
  )
  controller.teardown()

when isMainModule and not defined(merendaTests):
  runDirectLifetimes()
