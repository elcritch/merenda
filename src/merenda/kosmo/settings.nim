## Kosmo-specific application settings.

import ../nimkit as nimkit

const KosmoOptionAsMetaIdentifier* = "kosmo.settings.terminal.optionAsMeta"

type
  KosmoOptionAsMetaHandler* = proc(enabled: bool) {.closure.}

  KosmoSettingsWindow* = ref object of nimkit.Responder
    xWindow: nimkit.Panel
    xContentView: nimkit.View
    xFirstResponder: nimkit.Responder
    xOptionAsMetaButton: nimkit.Button
    xOptionAsMetaHandler: KosmoOptionAsMetaHandler

proc optionAsMeta*(settings: KosmoSettingsWindow): bool =
  ## Return the current terminal Option/Alt-as-Meta selection.
  not settings.isNil and settings.xOptionAsMetaButton.state == nimkit.bsOn

proc `optionAsMeta=`*(settings: KosmoSettingsWindow, enabled: bool) =
  ## Update the terminal Option/Alt-as-Meta selection without invoking its action.
  if not settings.isNil:
    settings.xOptionAsMetaButton.state = if enabled: nimkit.bsOn else: nimkit.bsOff

proc newKosmoSettingsWindow*(
    optionAsMeta = true, optionAsMetaHandler: KosmoOptionAsMetaHandler = nil
): KosmoSettingsWindow =
  ## Create Kosmo's settings panel, which intentionally contains no Merenda settings.
  result = KosmoSettingsWindow(
    xWindow: nimkit.newPanel("Kosmo Settings", nimkit.rect(180, 160, 480, 220)),
    xContentView: nimkit.newView(),
    xOptionAsMetaHandler: optionAsMetaHandler,
  )
  nimkit.initResponder(result)
  let
    settings = result
    layout = nimkit.newStackView(nimkit.laVertical)
    optionButton = nimkit.newCheckBox("Use Option/Alt as Meta")
    optionChanged = nimkit.actionSelector("kosmo.optionAsMetaChanged")
  result.xOptionAsMetaButton = optionButton
  result.xFirstResponder = optionButton

  optionButton.identifier = KosmoOptionAsMetaIdentifier
  optionButton.accessibilityLabel = "Use Option or Alt as Meta"
  optionButton.state = if optionAsMeta: nimkit.bsOn else: nimkit.bsOff
  optionButton.target = nimkit.newActionTarget(optionChanged) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not settings.xOptionAsMetaHandler.isNil:
      settings.xOptionAsMetaHandler(settings.optionAsMeta())
  optionButton.action = optionChanged

  layout.spacing = 12.0
  layout.alignment = nimkit.svaFill
  layout.addArrangedSubview(
    nimkit.newTitleLabel("Kosmo Settings"),
    nimkit.newHeadingLabel("Terminal"),
    optionButton,
    nimkit.newLabel(
      "Send Option/Alt-B and Option/Alt-F as Bash backward-word and forward-word " &
        "shortcuts."
    ),
  )
  layout.addFlexibleSpacer()
  result.xContentView.addSubview(layout)
  discard layout.pinEdges(
    toGuide = result.xContentView.contentLayoutGuide(nimkit.insets(22.0, 24.0)),
    edges = {nimkit.leLeft, nimkit.leTop, nimkit.leRight, nimkit.leBottom},
  )
  result.xWindow.automaticallyAdjustsContentMinSize = true

proc window*(settings: KosmoSettingsWindow): nimkit.Panel =
  ## Return the settings panel window.
  settings.xWindow

proc contentView*(settings: KosmoSettingsWindow): nimkit.View =
  ## Return the settings panel root view.
  settings.xContentView

proc firstResponder*(settings: KosmoSettingsWindow): nimkit.Responder =
  ## Return the control that should receive initial keyboard focus.
  settings.xFirstResponder
