import merenda/nimkit
import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Carousel", frame = rect(100, 100, 420, 260))
  root = newView()
  viewport = newView(frame = rect(24, 24, 372, 140))
  first = newGroupBox("Welcome", frame = rect(0, 0, 372, 140))
  second = newGroupBox("Details", frame = rect(372, 0, 372, 140))
  button = newButton("Next", frame = rect(24, 188, 160, 32))
  slideAction = actionSelector("slidePanels")

first.contentView = newLabel("Your first panel.")
second.contentView = newLabel("A little more information.")
viewport.clipsToBounds = true
var showingDetails = false

proc finishSlide(button: Button) {.slot.} =
  button.enabled = true

proc slidePanels(sender: DynamicAgent) =
  discard sender
  if button.enabled:
    button.enabled = false
    showingDetails = not showingDetails
    button.title = if showingDetails: "Back" else: "Next"
    let size = viewport.bounds.size
    let offset =
      if showingDetails:
        -size.width
      else:
        0.0'f32
    let slide = animationGroup(duration = 800.ms, curve = acLinear):
      first.frame = rect(offset, 0, size.width, size.height)
      second.frame = rect(offset + size.width, 0, size.width, size.height)
    slide.connect(finished, button, finishSlide)
    discard app.startAnimation(slide)

button.target = newActionTarget(slideAction, slidePanels)
button.action = slideAction
viewport.addSubview(first)
viewport.addSubview(second)
root.addSubview(viewport)
root.addSubview(button)
app.runWindow(window, root)
