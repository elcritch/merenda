## Extensible construction and property registry for NimKit resources.

import std/[sets, tables]

import sigils/selectors

import ../app/viewcontrollers
import ../containers/stackviews
import ../controls/[buttons, controls]
import ../drawing/images
import ../foundation/types
import ../text/textfields
import ../themes
import ../view/[imageviews, views]
import ./resourcecore

type
  ResourcePropertyContext* = object
    imageFor*: proc(id: ResourceId): ImageResource {.closure.}
    textFor*: proc(key, fallback: string): string {.closure.}

  ResourceViewFactory* = proc(frame: Rect): View {.closure.}
  ResourceControllerFactory* = proc(): ViewController {.closure.}
  ResourceChildAttacher* = proc(parent, child: View) {.closure.}
  ResourceViewPropertySetter* = proc(
    view: View, value: ResourceValue, context: ResourcePropertyContext
  ): bool {.closure.}

  ResourceViewPropertyRegistration* = object
    acceptedKinds*: set[ResourceValueKind]
    setter*: ResourceViewPropertySetter

  ResourceViewRegistration = object
    baseKind: string
    factory: ResourceViewFactory
    attachChild: ResourceChildAttacher

  ResourceRegistry* = object
    viewKinds: Table[string, ResourceViewRegistration]
    viewProperties: Table[string, Table[string, ResourceViewPropertyRegistration]]
    controllerKinds: Table[string, ResourceControllerFactory]
    actionSelectors: HashSet[string]
    chromeNames: HashSet[string]

proc initResourceRegistry*(): ResourceRegistry =
  ResourceRegistry(
    viewKinds: initTable[string, ResourceViewRegistration](),
    viewProperties: initTable[string, Table[string, ResourceViewPropertyRegistration]](),
    controllerKinds: initTable[string, ResourceControllerFactory](),
    actionSelectors: initHashSet[string](),
    chromeNames: initHashSet[string](),
  )

proc registerViewKind*(
    registry: var ResourceRegistry,
    kind: string,
    factory: ResourceViewFactory,
    baseKind = "view",
    attachChild: ResourceChildAttacher = nil,
) =
  registry.viewKinds[kind] = ResourceViewRegistration(
    baseKind: if kind == baseKind: "" else: baseKind,
    factory: factory,
    attachChild: attachChild,
  )

proc registerViewProperty*(
    registry: var ResourceRegistry,
    kind, name: string,
    acceptedKinds: set[ResourceValueKind],
    setter: ResourceViewPropertySetter,
) =
  registry.viewProperties.mgetOrPut(
    kind, initTable[string, ResourceViewPropertyRegistration]()
  )[name] =
    ResourceViewPropertyRegistration(acceptedKinds: acceptedKinds, setter: setter)

proc registerControllerKind*(
    registry: var ResourceRegistry, kind: string, factory: ResourceControllerFactory
) =
  registry.controllerKinds[kind] = factory

proc registerActionSelector*(registry: var ResourceRegistry, name: string) =
  if name.len > 0:
    registry.actionSelectors.incl name

proc registerChromeName*(registry: var ResourceRegistry, name: string) =
  if name.len > 0:
    registry.chromeNames.incl name

func hasViewKind*(registry: ResourceRegistry, kind: string): bool =
  registry.viewKinds.hasKey(kind)

func hasControllerKind*(registry: ResourceRegistry, kind: string): bool =
  registry.controllerKinds.hasKey(kind)

func hasActionSelector*(registry: ResourceRegistry, name: string): bool =
  registry.actionSelectors.contains(name)

func hasChromeName*(registry: ResourceRegistry, name: string): bool =
  registry.chromeNames.contains(name)

proc findViewProperty(
    registry: ResourceRegistry,
    kind, name: string,
    registration: var ResourceViewPropertyRegistration,
): bool =
  var current = kind
  for _ in 0 ..< 32:
    if registry.viewProperties.hasKey(current) and
        registry.viewProperties[current].hasKey(name):
      registration = registry.viewProperties[current][name]
      return true
    if not registry.viewKinds.hasKey(current):
      return
    current = registry.viewKinds[current].baseKind
    if current.len == 0:
      return

proc acceptsViewProperty*(
    registry: ResourceRegistry, kind, name: string, valueKind: ResourceValueKind
): bool =
  var registration: ResourceViewPropertyRegistration
  registry.findViewProperty(kind, name, registration) and
    valueKind in registration.acceptedKinds

proc constructView*(registry: ResourceRegistry, kind: string, frame: Rect): View =
  if registry.viewKinds.hasKey(kind):
    return registry.viewKinds[kind].factory(frame)

proc constructController*(registry: ResourceRegistry, kind: string): ViewController =
  if registry.controllerKinds.hasKey(kind):
    return registry.controllerKinds[kind]()

proc applyViewProperty*(
    registry: ResourceRegistry,
    kind: string,
    view: View,
    property: ResourceProperty,
    context: ResourcePropertyContext,
): bool =
  var registration: ResourceViewPropertyRegistration
  if registry.findViewProperty(kind, property.name, registration) and
      property.value.kind in registration.acceptedKinds:
    return registration.setter(view, property.value, context)

proc attachChild*(registry: ResourceRegistry, kind: string, parent, child: View) =
  if registry.viewKinds.hasKey(kind) and not registry.viewKinds[kind].attachChild.isNil:
    registry.viewKinds[kind].attachChild(parent, child)
  else:
    parent.addSubview(child)

proc textValue(value: ResourceValue, context: ResourcePropertyContext): string =
  if value.kind == rvString:
    return value.stringValue
  if value.kind == rvReference and value.referenceValue.kind == rrLocalizedString and
      not context.textFor.isNil:
    return context.textFor($value.referenceValue.id, value.stringValue)

proc enumNamed[T: enum](name: string, value: var T): bool =
  for candidate in T:
    if $candidate == name:
      value = candidate
      return true

proc registerCommonViewProperties(registry: var ResourceRegistry) =
  registry.registerViewProperty(
    "view",
    "frame",
    {rvRect},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.frame = value.rectValue
      true,
  )
  registry.registerViewProperty(
    "view",
    "identifier",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.identifier = value.stringValue
      true,
  )
  registry.registerViewProperty(
    "view",
    "hidden",
    {rvBool},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.hidden = value.boolValue
      true,
  )
  registry.registerViewProperty(
    "view",
    "background",
    {rvColor},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.background = value.colorValue
      true,
  )
  registry.registerViewProperty(
    "view",
    "alpha",
    {rvFloat},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.alphaValue = value.floatValue
      true,
  )
  registry.registerViewProperty(
    "view",
    "styleId",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.styleId = value.stringValue
      true,
  )
  registry.registerViewProperty(
    "view",
    "styleClasses",
    {rvStrings},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.styleClasses = value.stringValues
      true,
  )
  registry.registerViewProperty(
    "view",
    "toolTip",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.toolTip = value.stringValue
      true,
  )
  registry.registerViewProperty(
    "view",
    "tag",
    {rvInt},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      view.tag = value.intValue
      true,
  )

proc registerControlProperties(registry: var ResourceRegistry) =
  registry.registerViewProperty(
    "control",
    "enabled",
    {rvBool},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      Control(view).enabled = value.boolValue
      true,
  )

proc registerButtonProperties(registry: var ResourceRegistry) =
  registry.registerViewProperty(
    "button",
    "title",
    {rvString, rvReference},
    proc(view: View, value: ResourceValue, context: ResourcePropertyContext): bool =
      Button(view).title = value.textValue(context)
      true,
  )
  registry.registerViewProperty(
    "button",
    "state",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      var state: ButtonState
      if value.stringValue.enumNamed(state):
        Button(view).state = state
        return true
    ,
  )

proc registerTextFieldProperties(registry: var ResourceRegistry) =
  registry.registerViewProperty(
    "textField",
    "stringValue",
    {rvString, rvReference},
    proc(view: View, value: ResourceValue, context: ResourcePropertyContext): bool =
      TextField(view).stringValue = value.textValue(context)
      true,
  )
  registry.registerViewProperty(
    "textField",
    "alignment",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      var alignment: TextAlignment
      if value.stringValue.enumNamed(alignment):
        TextField(view).alignment = alignment
        return true
    ,
  )
  registry.registerViewProperty(
    "textField",
    "editable",
    {rvBool},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      TextField(view).editable = value.boolValue
      true,
  )
  registry.registerViewProperty(
    "textField",
    "selectable",
    {rvBool},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      TextField(view).selectable = value.boolValue
      true,
  )

proc registerStackViewProperties(registry: var ResourceRegistry) =
  registry.registerViewProperty(
    "stackView",
    "orientation",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      var orientation: LayoutAxis
      if value.stringValue.enumNamed(orientation):
        StackView(view).orientation = orientation
        return true
    ,
  )
  registry.registerViewProperty(
    "stackView",
    "spacing",
    {rvFloat},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      StackView(view).spacing = value.floatValue
      true,
  )
  registry.registerViewProperty(
    "stackView",
    "edgeInsets",
    {rvInsets},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      StackView(view).edgeInsets = value.insetsValue
      true,
  )
  registry.registerViewProperty(
    "stackView",
    "alignment",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      var alignment: StackViewAlignment
      if value.stringValue.enumNamed(alignment):
        StackView(view).alignment = alignment
        return true
    ,
  )
  registry.registerViewProperty(
    "stackView",
    "distribution",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      var distribution: StackViewDistribution
      if value.stringValue.enumNamed(distribution):
        StackView(view).distribution = distribution
        return true
    ,
  )

proc registerImageViewProperties(registry: var ResourceRegistry) =
  registry.registerViewProperty(
    "imageView",
    "image",
    {rvReference},
    proc(view: View, value: ResourceValue, context: ResourcePropertyContext): bool =
      if value.referenceValue.kind == rrImage and not context.imageFor.isNil:
        ImageView(view).setImage(context.imageFor(value.referenceValue.id))
        return true
    ,
  )
  registry.registerViewProperty(
    "imageView",
    "imageScaling",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      var scaling: ImageScaling
      if value.stringValue.enumNamed(scaling):
        ImageView(view).setImageScaling(scaling)
        return true
    ,
  )
  registry.registerViewProperty(
    "imageView",
    "imageAlignment",
    {rvString},
    proc(view: View, value: ResourceValue, _: ResourcePropertyContext): bool =
      var alignment: ImageAlignment
      if value.stringValue.enumNamed(alignment):
        ImageView(view).setImageAlignment(alignment)
        return true
    ,
  )

proc initNimKitResourceRegistry*(): ResourceRegistry =
  result = initResourceRegistry()
  result.registerViewKind(
    "view",
    proc(frame: Rect): View =
      newView(frame),
    baseKind = "",
  )
  result.registerViewKind(
    "control",
    proc(frame: Rect): View =
      let control = Control()
      initControlFields(control, frame)
      control,
    baseKind = "view",
  )
  result.registerViewKind(
    "button",
    proc(frame: Rect): View =
      newButton(frame = frame),
    baseKind = "control",
  )
  result.registerViewKind(
    "checkBox",
    proc(frame: Rect): View =
      newCheckBox(frame = frame),
    baseKind = "button",
  )
  result.registerViewKind(
    "radioButton",
    proc(frame: Rect): View =
      newRadioButton(frame = frame),
    baseKind = "button",
  )
  result.registerViewKind(
    "textField",
    proc(frame: Rect): View =
      newTextField(frame = frame),
    baseKind = "control",
  )
  result.registerViewKind(
    "label",
    proc(frame: Rect): View =
      newLabel(frame = frame),
    baseKind = "textField",
  )
  result.registerViewKind(
    "imageView",
    proc(frame: Rect): View =
      newImageView(frame = frame),
    baseKind = "view",
  )
  result.registerViewKind(
    "stackView",
    proc(frame: Rect): View =
      newStackView(frame = frame),
    baseKind = "view",
    attachChild = proc(parent, child: View) =
      StackView(parent).addArrangedSubview(child),
  )
  result.registerControllerKind(
    "viewController",
    proc(): ViewController =
      newViewController(),
  )

  result.registerCommonViewProperties()
  result.registerControlProperties()
  result.registerButtonProperties()
  result.registerTextFieldProperties()
  result.registerStackViewProperties()
  result.registerImageViewProperties()

  for name in [
    "cancelOperation", "complete", "copy", "cut", "deleteBackward", "deleteForward",
    "hide", "hideOtherApplications", "insertNewline", "insertTab", "newDocument",
    "openDocument", "orderFrontStandardAboutPanel", "paste", "performClick",
    "performClose", "performMiniaturize", "performZoom", "printDocument", "redo",
    "saveDocument", "saveDocumentAs", "selectAll", "selectNextKeyView",
    "selectPreviousKeyView", "terminate", "toggleFullScreen", "undo",
    "unhideAllApplications",
  ]:
    result.registerActionSelector(name)
  result.registerChromeName(DefaultChromeName)
  result.registerChromeName(AquaChromeName)
  result.registerChromeName(FlatTransparentChromeName)
