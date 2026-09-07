## The persistent context area above Kosmo's Files and Find tabs.

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout

const KosmoContextPanelHeight* = 216.0'f32
  ## Initial height: approximately twelve compact text lines.

type KosmoContextPanel* = ref object of nimkit.View
  titleLabel: nimkit.Label

protocol KosmoContextPanelLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(panel: KosmoContextPanel) =
    let bounds = panel.bounds()
    panel.titleLabel.setFrameFromLayout(
      nimkit.rect(12, 4, max(bounds.size.width - 24, 0), min(bounds.size.height, 24))
    )

proc newKosmoContextPanel*(): KosmoContextPanel =
  ## Create an empty context panel, ready for contextual content.
  result = KosmoContextPanel(titleLabel: nimkit.newLabel("Context"))
  result.initViewFields()
  result.identifier = "kosmo.context"
  result.accessibilityLabel = "Context"
  result.clipsToBounds = true
  result.addSubview(result.titleLabel)
  discard result.withProtocol(KosmoContextPanelLayout)
