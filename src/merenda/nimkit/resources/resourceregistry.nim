## Extensible construction and property registry for NimKit resources.

import std/[algorithm, options, sets, strutils, tables]

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
  ResourceRegistryLookupError* = object of CatchableError

  ResourceViewKindDescriptor* = object
    kind*: string
    baseKind*: string

  ResourcePropertyDescriptor* = object
    name*: string
    declaredKind*: string
    aliasOf*: string
    getterSelectorName*: string
    setterSelectorName*: string
    nimTypeName*: string
    acceptedKinds*: set[ResourceValueKind]
    inherited*: bool
    editable*: bool

  ResourcePropertyContext* = object
    imageFor*: proc(id: ResourceId): ImageResource {.closure.}
    textFor*: proc(key, fallback: string): string {.closure.}

  ResourceViewFactory* = proc(frame: Rect): View {.closure.}
  ResourceControllerFactory* = proc(): ViewController {.closure.}
  ResourceChildAttacher* = proc(parent, child: View) {.closure.}
  ResourceValueDecoder*[T] = proc(
    value: ResourceValue, context: ResourcePropertyContext, decoded: var T
  ): bool {.closure.}
  ResourceViewPropertySetter* = proc(
    view: View, value: ResourceValue, context: ResourcePropertyContext
  ): bool {.closure.}

  ResourcePropertyValueApplier = proc(
    view: View,
    selectorName: SigilName,
    value: ResourceValue,
    context: ResourcePropertyContext,
  ): bool {.closure.}

  ResourcePropertyValueRegistration = object
    acceptedKinds: set[ResourceValueKind]
    apply: ResourcePropertyValueApplier

  ResourceViewPropertyRegistration* = object
    acceptedKinds*: set[ResourceValueKind]
    selector*: SigilName
    getterSelector: SigilName
    aliasOf: string
    valueType*: string
    setter*: ResourceViewPropertySetter

  ResourceViewRegistration = object
    baseKind: string
    factory: ResourceViewFactory
    attachChild: ResourceChildAttacher

  ResourceRegistry* = object
    viewKinds: Table[string, ResourceViewRegistration]
    viewProperties: Table[string, Table[string, ResourceViewPropertyRegistration]]
    propertyValueTypes: Table[string, ResourcePropertyValueRegistration]
    controllerKinds: Table[string, ResourceControllerFactory]
    actionSelectors: HashSet[string]
    chromeNames: HashSet[string]

proc initResourceRegistry*(): ResourceRegistry =
  ResourceRegistry(
    viewKinds: initTable[string, ResourceViewRegistration](),
    viewProperties: initTable[string, Table[string, ResourceViewPropertyRegistration]](),
    propertyValueTypes: initTable[string, ResourcePropertyValueRegistration](),
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

proc registerResourceValueType*[T](
    registry: var ResourceRegistry,
    typeName: string,
    acceptedKinds: set[ResourceValueKind],
    decoder: ResourceValueDecoder[T],
) =
  ## Register one conversion from resource data to a Sigils property value type.
  let applyValue: ResourcePropertyValueApplier = proc(
      view: View,
      selectorName: SigilName,
      value: ResourceValue,
      context: ResourcePropertyContext,
  ): bool =
    var decoded: T
    if not decoder(value, context, decoded):
      return
    let setter = selector[T, tuple[]]($selectorName)
    DynamicAgent(view).sendLocalIfHandled(setter, decoded)

  registry.propertyValueTypes[typeName] =
    ResourcePropertyValueRegistration(acceptedKinds: acceptedKinds, apply: applyValue)

func localSelectorName(name: string): string =
  let separator = name.rfind('.')
  if separator < 0:
    name
  else:
    name[separator + 1 .. ^1]

func selectorPrefix(name: string): string =
  let separator = name.rfind('.')
  if separator >= 0:
    result = name[0 .. separator]

func propertyNameForSetter(selectorName: string): string =
  let localName = selectorName.localSelectorName()
  if localName.len > 1 and localName.endsWith('='):
    return localName[0 .. ^2]
  if localName.len <= 3 or not localName.startsWith("set") or
      not localName[3].isUpperAscii:
    return
  result = localName[3 .. ^1]
  result[0] = result[0].toLowerAscii

func propertyTypeFromSignature(signature: string): string =
  const valueMarker = "(value: "
  let
    valueStart = signature.find(valueMarker)
    valueStop = signature.rfind(')')
  if valueStart < 0 or valueStop <= valueStart + valueMarker.high:
    return
  signature[valueStart + valueMarker.len ..< valueStop].strip()

proc registerViewProtocolProperties*(
    registry: var ResourceRegistry, kind: string, protocol: SigilProtocol
) =
  ## Discover property getter/setter pairs from a Sigils protocol.
  for requirement in protocol.requirements:
    let
      setterName = $requirement.selector
      propertyName = setterName.propertyNameForSetter()
      valueType = requirement.signature.propertyTypeFromSignature()
    if propertyName.len > 0 and valueType.len > 0:
      let getterName = setterName.selectorPrefix() & propertyName
      if protocol.hasRequirement(toSigilName(getterName)):
        let acceptedKinds =
          if registry.propertyValueTypes.hasKey(valueType):
            registry.propertyValueTypes[valueType].acceptedKinds
          else:
            {}

        registry.viewProperties.mgetOrPut(
          kind, initTable[string, ResourceViewPropertyRegistration]()
        )[propertyName] = ResourceViewPropertyRegistration(
          acceptedKinds: acceptedKinds,
          selector: requirement.selector,
          getterSelector: toSigilName(getterName),
          valueType: valueType,
        )

proc registerViewPropertyAlias*(
    registry: var ResourceRegistry, kind, alias, propertyName: string
) =
  ## Register a resource spelling for an already-discovered property.
  if registry.viewProperties.hasKey(kind) and
      registry.viewProperties[kind].hasKey(propertyName):
    registry.viewProperties[kind][alias] = registry.viewProperties[kind][propertyName]
    registry.viewProperties[kind][alias].aliasOf = propertyName

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
    declaredKind: var string,
): bool =
  var current = kind
  for _ in 0 ..< 32:
    if registry.viewProperties.hasKey(current) and
        registry.viewProperties[current].hasKey(name):
      registration = registry.viewProperties[current][name]
      declaredKind = current
      return true
    if not registry.viewKinds.hasKey(current):
      return
    current = registry.viewKinds[current].baseKind
    if current.len == 0:
      return

proc missingRegistryEntry(kind, name: string) {.noinline, noreturn.} =
  raise newException(
    ResourceRegistryLookupError,
    "resource " & kind & " descriptor '" & name & "' is unavailable",
  )

func findViewKindDescriptor*(
    registry: ResourceRegistry, kind: string
): Option[ResourceViewKindDescriptor] =
  ## Returns a public, non-factory view-kind description when registered.
  if registry.viewKinds.hasKey(kind):
    return some(
      ResourceViewKindDescriptor(
        kind: kind, baseKind: registry.viewKinds[kind].baseKind
      )
    )

proc viewKindDescriptor*(
    registry: ResourceRegistry, kind: string
): ResourceViewKindDescriptor =
  ## Returns a required view-kind description.
  let found = registry.findViewKindDescriptor(kind)
  if found.isNone:
    missingRegistryEntry("view kind", kind)
  found.get()

iterator viewKinds*(registry: ResourceRegistry): ResourceViewKindDescriptor =
  ## Iterates registered view kinds in deterministic name order.
  var names: seq[string]
  for name in registry.viewKinds.keys:
    names.add name
  names.sort()
  for name in names:
    yield ResourceViewKindDescriptor(
      kind: name, baseKind: registry.viewKinds[name].baseKind
    )

func propertyAcceptedKinds(
    registry: ResourceRegistry, registration: ResourceViewPropertyRegistration
): set[ResourceValueKind] =
  if not registration.setter.isNil:
    registration.acceptedKinds
  elif registry.propertyValueTypes.hasKey(registration.valueType):
    registry.propertyValueTypes[registration.valueType].acceptedKinds
  else:
    {}

func propertyDescriptor(
    registry: ResourceRegistry,
    requestedKind, declaredKind, name: string,
    registration: ResourceViewPropertyRegistration,
): ResourcePropertyDescriptor =
  let acceptedKinds = registry.propertyAcceptedKinds(registration)
  ResourcePropertyDescriptor(
    name: name,
    declaredKind: declaredKind,
    aliasOf: registration.aliasOf,
    getterSelectorName: $registration.getterSelector,
    setterSelectorName: $registration.selector,
    nimTypeName: registration.valueType,
    acceptedKinds: acceptedKinds,
    inherited: requestedKind != declaredKind,
    editable: not registration.setter.isNil or acceptedKinds != {},
  )

func findViewPropertyDescriptor*(
    registry: ResourceRegistry, kind, name: string
): Option[ResourcePropertyDescriptor] =
  ## Describes a directly declared or inherited resource property.
  var
    registration: ResourceViewPropertyRegistration
    declaredKind: string
  if registry.findViewProperty(kind, name, registration, declaredKind):
    return some(registry.propertyDescriptor(kind, declaredKind, name, registration))

proc viewPropertyDescriptor*(
    registry: ResourceRegistry, kind, name: string
): ResourcePropertyDescriptor =
  ## Returns a required directly declared or inherited property description.
  let found = registry.findViewPropertyDescriptor(kind, name)
  if found.isNone:
    missingRegistryEntry("view property", kind & "." & name)
  found.get()

iterator viewProperties*(
    registry: ResourceRegistry, kind: string
): ResourcePropertyDescriptor =
  ## Iterates effective properties for a view kind in deterministic name order.
  var
    descriptors: seq[ResourcePropertyDescriptor]
    names = initHashSet[string]()
    current = kind
  for _ in 0 ..< 32:
    if registry.viewProperties.hasKey(current):
      for name, registration in registry.viewProperties[current].pairs:
        if name notin names:
          names.incl name
          descriptors.add(
            registry.propertyDescriptor(kind, current, name, registration)
          )
    if not registry.viewKinds.hasKey(current):
      break
    current = registry.viewKinds[current].baseKind
    if current.len == 0:
      break
  descriptors.sort(
    proc(a, b: ResourcePropertyDescriptor): int =
      cmp(a.name, b.name)
  )
  for descriptor in descriptors:
    yield descriptor

proc acceptsViewProperty*(
    registry: ResourceRegistry, kind, name: string, valueKind: ResourceValueKind
): bool =
  var
    registration: ResourceViewPropertyRegistration
    declaredKind: string
  if registry.findViewProperty(kind, name, registration, declaredKind):
    if not registration.setter.isNil:
      return valueKind in registration.acceptedKinds
    if registry.propertyValueTypes.hasKey(registration.valueType):
      return
        valueKind in registry.propertyValueTypes[registration.valueType].acceptedKinds

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
  var
    registration: ResourceViewPropertyRegistration
    declaredKind: string
  if registry.findViewProperty(kind, property.name, registration, declaredKind):
    if not registration.setter.isNil and
        property.value.kind in registration.acceptedKinds:
      return registration.setter(view, property.value, context)
    if registry.propertyValueTypes.hasKey(registration.valueType):
      let valueType = registry.propertyValueTypes[registration.valueType]
      if property.value.kind in valueType.acceptedKinds:
        return valueType.apply(view, registration.selector, property.value, context)

proc attachChild*(registry: ResourceRegistry, kind: string, parent, child: View) =
  if registry.viewKinds.hasKey(kind) and not registry.viewKinds[kind].attachChild.isNil:
    registry.viewKinds[kind].attachChild(parent, child)
  else:
    parent.addSubview(child)

proc enumNamed[T: enum](name: string, value: var T): bool =
  for candidate in T:
    if $candidate == name:
      value = candidate
      return true

proc decodeBool(
    value: ResourceValue, _: ResourcePropertyContext, decoded: var bool
): bool =
  if value.kind == rvBool:
    decoded = value.boolValue
    return true

proc decodeInt(
    value: ResourceValue, _: ResourcePropertyContext, decoded: var int
): bool =
  if value.kind == rvInt:
    decoded = value.intValue
    return true

proc decodeFloat32(
    value: ResourceValue, _: ResourcePropertyContext, decoded: var float32
): bool =
  if value.kind == rvFloat:
    decoded = value.floatValue
    return true

proc decodeString(
    value: ResourceValue, context: ResourcePropertyContext, decoded: var string
): bool =
  if value.kind == rvString:
    decoded = value.stringValue
    return true
  if value.kind == rvReference and value.referenceValue.kind == rrLocalizedString and
      not context.textFor.isNil:
    decoded = context.textFor($value.referenceValue.id, value.stringValue)
    return true

proc decodeStrings(
    value: ResourceValue, _: ResourcePropertyContext, decoded: var seq[string]
): bool =
  if value.kind == rvStrings:
    decoded = value.stringValues
    return true

proc decodeRect(
    value: ResourceValue, _: ResourcePropertyContext, decoded: var Rect
): bool =
  if value.kind == rvRect:
    decoded = value.rectValue
    return true

proc decodeSize(
    value: ResourceValue, _: ResourcePropertyContext, decoded: var Size
): bool =
  if value.kind == rvSize:
    decoded = value.sizeValue
    return true

proc decodeInsets(
    value: ResourceValue, _: ResourcePropertyContext, decoded: var EdgeInsets
): bool =
  if value.kind == rvInsets:
    decoded = value.insetsValue
    return true

proc decodeColor(
    value: ResourceValue, _: ResourcePropertyContext, decoded: var Color
): bool =
  if value.kind == rvColor:
    decoded = value.colorValue
    return true

proc decodeImage(
    value: ResourceValue, context: ResourcePropertyContext, decoded: var ImageResource
): bool =
  if value.kind == rvReference and value.referenceValue.kind == rrImage and
      not context.imageFor.isNil:
    decoded = context.imageFor(value.referenceValue.id)
    return true

proc decodeEnum[T: enum](
    value: ResourceValue, _: ResourcePropertyContext, decoded: var T
): bool =
  value.kind == rvString and value.stringValue.enumNamed(decoded)

proc registerResourceEnumType*[T: enum](
    registry: var ResourceRegistry, typeName: string
) =
  registerResourceValueType[T](registry, typeName, {rvString}, decodeEnum[T])

proc registerDefaultResourceValueTypes(registry: var ResourceRegistry) =
  registerResourceValueType[bool](registry, "bool", {rvBool}, decodeBool)
  registerResourceValueType[int](registry, "int", {rvInt}, decodeInt)
  registerResourceValueType[float32](registry, "float32", {rvFloat}, decodeFloat32)
  registerResourceValueType[string](
    registry, "string", {rvString, rvReference}, decodeString
  )
  registerResourceValueType[seq[string]](
    registry, "seq[string]", {rvStrings}, decodeStrings
  )
  registerResourceValueType[Rect](registry, "Rect", {rvRect}, decodeRect)
  registerResourceValueType[Size](registry, "Size", {rvSize}, decodeSize)
  registerResourceValueType[EdgeInsets](
    registry, "EdgeInsets", {rvInsets}, decodeInsets
  )
  registerResourceValueType[Color](registry, "Color", {rvColor}, decodeColor)
  registerResourceValueType[ImageResource](
    registry, "ImageResource", {rvReference}, decodeImage
  )

  registerResourceEnumType[ButtonState](registry, "ButtonState")
  registerResourceEnumType[ButtonType](registry, "ButtonType")
  registerResourceEnumType[FocusRingType](registry, "FocusRingType")
  registerResourceEnumType[TextAlignment](registry, "TextAlignment")
  registerResourceEnumType[LayoutAxis](registry, "LayoutAxis")
  registerResourceEnumType[StackViewAlignment](registry, "StackViewAlignment")
  registerResourceEnumType[StackViewDistribution](registry, "StackViewDistribution")
  registerResourceEnumType[ImageScaling](registry, "ImageScaling")
  registerResourceEnumType[ImageAlignment](registry, "ImageAlignment")

proc initNimKitResourceRegistry*(): ResourceRegistry =
  result = initResourceRegistry()
  result.registerDefaultResourceValueTypes()
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

  result.registerViewProtocolProperties("view", ViewProtocol)
  result.registerViewPropertyAlias("view", "background", "backgroundColor")
  result.registerViewPropertyAlias("view", "alpha", "alphaValue")
  result.registerViewProtocolProperties("control", ControlProtocol)
  result.registerViewProtocolProperties("button", ButtonProtocol)
  result.registerViewProtocolProperties("textField", TextFieldProtocol)
  result.registerViewProtocolProperties("stackView", StackViewProtocol)
  result.registerViewPropertyAlias("stackView", "alignment", "stackAlignment")
  result.registerViewProtocolProperties("imageView", ImageViewProtocol)

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
