## Import GUI markup with HTML5 syntax as ordinary, editable NimKit resources.
##
## GUI elements describe widgets and their children; `data-*` attributes describe
## native properties. Parsing creates no views or windows. Call `instantiateResources`
## on a successfully loaded bundle to construct the interface.

import
  std/[algorithm, htmlparser, options, os, sets, streams, strtabs, strutils, xmltree]

import ../foundation/types
import ../themes/themecore
import ./[resrccore, resrcregistry, resrcvalidation]
import ./private/[htmlsyntax, htmlvalues]

type
  GuiContentKind = enum
    gckChildren
    gckLabel
    gckText
    gckMultiline
    gckTitle
    gckOptions

  GuiImport = object
    registry: ResourceRegistry
    loaded: ResourceLoadResult
    identifiers: HashSet[string]
    nextIdentifier: int
    viewDepth: int
    documentDepth: int
    importingWindow: bool

const
  browserTags = [
    "html", "head", "body", "main", "form", "article", "aside", "nav", "figure",
    "figcaption", "ul", "ol", "li", "meta", "title", "link", "div", "header", "footer",
    "p", "h1", "h2", "h3", "h4", "h5", "h6", "output",
  ]
  inlineTags = ["span", "strong", "em", "b", "i", "code", "br"]

proc hasAttribute(node: XmlNode, name: string): bool =
  if not node.attrs.isNil:
    for key in node.attrs.keys:
      if cmpIgnoreCase(key, name) == 0:
        return true

proc attribute(node: XmlNode, name: string, fallback = ""): string =
  if not node.attrs.isNil:
    for key, value in node.attrs.pairs:
      if cmpIgnoreCase(key, name) == 0:
        return value
  fallback

proc nextId(state: var GuiImport, kind: string): ResourceId =
  while true:
    inc state.nextIdentifier
    let name = "gui." & kind & "." & $state.nextIdentifier
    if name notin state.identifiers:
      state.identifiers.incl name
      return resourceId(name)

proc error(state: var GuiImport, code, message, path: string, id = resourceId("")) =
  state.loaded.diagnostics.add(rdsError, code, message, path = path, resourceId = id)

proc put(node: var ViewNodeResource, name: string, value: ResourceValue) =
  for property in node.properties.mitems:
    if property.name == name:
      property.value = value
      return
  node.properties.add resourceProperty(name, value)

proc putAttribute(
    state: var GuiImport, view: var ViewNodeResource, name, value, path: string
) =
  let key = name.attributeKey()
  for descriptor in state.registry.viewProperties(view.kind):
    if descriptor.name.attributeKey() == key:
      try:
        view.put(descriptor.name, htmlValue(value, descriptor))
      except ValueError as exception:
        state.error("gui.attribute.invalid", exception.msg, path, view.id)
      return
  state.error(
    "gui.attribute.unsupported",
    "property '" & name & "' is not registered for " & view.kind,
    path,
    view.id,
  )

proc appendText(
    state: var GuiImport,
    node: XmlNode,
    text: var string,
    pendingSpace: var bool,
    path: string,
) =
  case node.kind
  of xnText, xnVerbatimText, xnCData, xnEntity:
    for ch in node.text:
      if ch in {' ', '\t', '\r', '\n', '\f'}:
        pendingSpace = text.len > 0 and text[^1] != '\n'
      else:
        if pendingSpace:
          text.add ' '
          pendingSpace = false
        text.add ch
  of xnElement:
    if node.tag == "br":
      text.add '\n'
      pendingSpace = false
    elif node.tag in inlineTags:
      for child in node:
        state.appendText(child, text, pendingSpace, path)
    else:
      state.error(
        "gui.element.unsupportedChild",
        "<" & node.tag & "> cannot appear inside text content",
        path,
      )
  else:
    discard

proc textContent(state: var GuiImport, node: XmlNode, path: string): string =
  var pendingSpace: bool
  if node.kind == xnElement:
    for child in node:
      state.appendText(child, result, pendingSpace, path)
  else:
    state.appendText(node, result, pendingSpace, path)

proc viewKind(state: var GuiImport, node: XmlNode, path: string): string =
  if node.tag in browserTags:
    state.error(
      "gui.element.unsupported",
      "<" & node.tag & "> is not a GUI element; use nk-main or native nk-* views",
      path,
    )
    return
  if node.hasAttribute("data-kind"):
    if node.tag == "nk-view":
      return node.attribute("data-kind")
    state.error("gui.kind.override", "data-kind is supported only on nk-view", path)
    return
  if node.tag == "section":
    return "stackView"
  if node.tag in inlineTags:
    return "label"
  case node.tag
  of "button":
    "button"
  of "img":
    "imageView"
  of "progress":
    "progressIndicator"
  of "select":
    "comboBox"
  of "textarea":
    "textView"
  of "input":
    case node.attribute("type", "text").toLowerAscii()
    of "text", "search", "email", "url", "tel":
      "textField"
    of "checkbox":
      "checkBox"
    of "radio":
      "radioButton"
    of "range":
      "slider"
    of "number":
      "stepper"
    of "button":
      "button"
    else:
      state.error(
        "gui.input.unsupported",
        "unsupported input type: " & node.attribute("type"),
        path,
      )
      ""
  else:
    let native = node.tag.startsWith("nk-")
    let name =
      if native:
        node.tag[3 ..^ 1]
      else:
        node.tag
    var matchedKind: string
    for descriptor in state.registry.viewKinds:
      # Application tags use their full hyphenated registered name. Native kinds
      # use nk- plus the registry name in kebab case.
      if (native or '-' in descriptor.kind) and
          descriptor.kind.attributeKey() == name.attributeKey():
        if matchedKind.len > 0:
          state.error(
            "gui.kind.ambiguous",
            "multiple registered kinds match <" & node.tag & ">",
            path,
          )
          return
        matchedKind = descriptor.kind
    if matchedKind.len > 0:
      return matchedKind
    state.error(
      "gui.element.unsupported", "unsupported GUI element <" & node.tag & ">", path
    )
    ""

proc contentKind(registry: ResourceRegistry, kind: string): GuiContentKind =
  var current = kind
  var visited = initHashSet[string]()
  while current.len > 0 and current notin visited:
    visited.incl current
    case current
    of "label":
      return gckLabel
    of "textField":
      return gckText
    of "textView":
      return gckMultiline
    of "button":
      return gckTitle
    of "comboBox":
      return gckOptions
    else:
      discard
    let descriptor = registry.findViewKindDescriptor(current)
    if descriptor.isNone:
      break
    current = descriptor.get().baseKind

proc hasContent(source: XmlNode): bool =
  for child in source:
    if child.kind == xnElement or (
      child.kind in {xnText, xnVerbatimText, xnCData, xnEntity} and
      child.text.strip().len > 0
    ):
      return true

proc configureSelect(
    state: var GuiImport, source: XmlNode, view: var ViewNodeResource, path: string
) =
  var
    titles, values: seq[string]
    selected = 0
    selectionSeen: bool
  if source.hasAttribute("multiple"):
    state.error(
      "gui.select.multiple", "select supports a single selection", path, view.id
    )
  for child in source:
    if child.kind == xnElement:
      if child.tag != "option":
        state.error(
          "gui.element.unsupportedChild", "select requires option children", path,
          view.id,
        )
      else:
        let text = state.textContent(child, path)
        titles.add child.attribute("label", text)
        values.add child.attribute("value", text)
        if child.hasAttribute("disabled"):
          state.error(
            "gui.option.disabled", "disabled options are not supported", path, view.id
          )
        if child.hasAttribute("selected"):
          if selectionSeen:
            state.error(
              "gui.select.selection", "select has more than one selected option", path,
              view.id,
            )
          selected = titles.high
          selectionSeen = true
    elif child.kind in {xnText, xnVerbatimText, xnCData, xnEntity} and
        child.text.strip().len > 0:
      state.error(
        "gui.select.content", "put option text inside option elements", path, view.id
      )
  view.put("editable", resourceValue(false))
  view.put("items", resourceValue(titles))
  view.put("itemValues", resourceValue(values))
  view.put("selectedIndex", resourceValue(if titles.len == 0: -1 else: selected))

proc configureElement(
    state: var GuiImport, source: XmlNode, view: var ViewNodeResource, path: string
) =
  case source.tag
  of "button":
    view.put("title", resourceValue(state.textContent(source, path)))
  of "input":
    case source.attribute("type", "text").toLowerAscii()
    of "checkbox", "radio":
      view.put(
        "state", resourceValue(if source.hasAttribute("checked"): "bsOn" else: "bsOff")
      )
    of "range", "number":
      state.putAttribute(
        view, "maxValue", source.attribute("max", "100"), path & "/@max"
      )
      state.putAttribute(view, "minValue", source.attribute("min", "0"), path & "/@min")
      let stepName = if view.kind == "stepper": "increment" else: "stepValue"
      state.putAttribute(view, stepName, source.attribute("step", "1"), path & "/@step")
      state.putAttribute(
        view, "value", source.attribute("value", "0"), path & "/@value"
      )
    of "button":
      view.put("title", resourceValue(source.attribute("value")))
    else:
      view.put("stringValue", resourceValue(source.attribute("value")))
  of "textarea":
    # Preserve authored newlines and indentation, as HTML textarea does.
    view.put("stringValue", resourceValue(source.innerText))
  of "select":
    state.configureSelect(source, view, path)
  of "progress":
    view.put("minValue", resourceValue(0.0'f32))
    state.putAttribute(view, "maxValue", source.attribute("max", "1"), path & "/@max")
    view.put("indeterminate", resourceValue(not source.hasAttribute("value")))
    if source.hasAttribute("value"):
      state.putAttribute(view, "value", source.attribute("value"), path & "/@value")
  of "img":
    let src = source.attribute("src")
    if src.len == 0:
      state.error("gui.image.sourceMissing", "img requires src", path, view.id)
    else:
      let id = state.nextId("image")
      state.loaded.bundle.images.add ImageAssetResource(
        id: id, sourceKind: risFile, path: src
      )
      view.put("image", resourceValue(resourceReference(rrImage, id)))
    if source.hasAttribute("alt"):
      view.put("toolTip", resourceValue(source.attribute("alt")))
  else:
    case state.registry.contentKind(view.kind)
    of gckLabel, gckText:
      view.put(
        "stringValue",
        resourceValue(source.attribute("value", state.textContent(source, path))),
      )
    of gckMultiline:
      for child in source:
        if child.kind == xnElement:
          state.error(
            "gui.element.unsupportedChild",
            "escape literal markup inside native text views, or use textarea", path,
            view.id,
          )
      view.put("stringValue", resourceValue(source.innerText))
    of gckTitle:
      view.put("title", resourceValue(state.textContent(source, path)))
    of gckOptions:
      if source.hasContent():
        state.configureSelect(source, view, path)
    of gckChildren:
      discard

proc configureAttributes(
    state: var GuiImport, source: XmlNode, view: var ViewNodeResource, path: string
) =
  let content = state.registry.contentKind(view.kind)
  if source.hasAttribute("id"):
    view.put("styleId", resourceValue(source.attribute("id")))
  if source.hasAttribute("title"):
    view.put("toolTip", resourceValue(source.attribute("title")))
  if source.hasAttribute("hidden"):
    view.put("hidden", resourceValue(true))
  if source.hasAttribute("checked"):
    state.putAttribute(view, "state", "on", path & "/@checked")
  if source.hasAttribute("disabled"):
    if content == gckMultiline:
      view.put("editable", resourceValue(false))
      view.put("selectable", resourceValue(false))
    else:
      state.putAttribute(view, "enabled", "false", path & "/@disabled")
  if source.hasAttribute("readonly"):
    state.putAttribute(view, "editable", "false", path & "/@readonly")
  if source.hasAttribute("placeholder"):
    state.putAttribute(
      view, "placeholder", source.attribute("placeholder"), path & "/@placeholder"
    )

  var attributes: seq[string]
  if not source.attrs.isNil:
    for name in source.attrs.keys:
      attributes.add name
  attributes.sort()
  for originalName in attributes:
    let
      name = originalName.toLowerAscii()
      value = source.attrs[originalName]
      attributePath = path & "/@" & name
    if name.startsWith("data-") and name != "data-kind":
      let property =
        case name
        of "data-axis":
          "orientation"
        of "data-padding":
          "edgeInsets"
        else:
          name[5 ..^ 1]
      state.putAttribute(view, property, value, attributePath)
    elif name == "style" or name.startsWith("on"):
      state.error(
        "gui.attribute.unsupported",
        "use native data-* properties or wire behavior in Nim", attributePath, view.id,
      )

  if source.hasAttribute("class") and not source.hasAttribute("data-style-classes"):
    var classes: seq[string]
    if content == gckLabel:
      classes.add LabelStyleClass
      for property in view.properties:
        if property.name == "labelStyle":
          case property.value.stringValue
          of "lsTitle":
            classes.add LabelTitleStyleClass
          of "lsHeading":
            classes.add LabelHeadingStyleClass
          of "lsStatus":
            classes.add LabelStatusStyleClass
          of "lsForm":
            classes.add LabelFormStyleClass
          else:
            discard
    for class in source.attribute("class").splitWhitespace():
      if class notin classes:
        classes.add class
    view.put("styleClasses", resourceValue(classes))

proc importNodes(
  state: var GuiImport, source: XmlNode, path: string
): seq[ViewNodeResource]

proc importWindow(
  state: var GuiImport, source: XmlNode, path: string
): seq[ViewNodeResource]

proc importChildren(
    state: var GuiImport, source: XmlNode, path: string
): seq[ViewNodeResource] =
  var
    text: string
    pendingSpace: bool
  template flushText() =
    if text.len > 0:
      result.add initViewNodeResource(
        state.nextId("text"),
        "label",
        [resourceProperty("stringValue", resourceValue(text))],
      )
      text.setLen(0)
      pendingSpace = false

  for index in 0 ..< source.len:
    let child = source[index]
    let childPath = path & "/" & $index
    if child.kind in {xnText, xnVerbatimText, xnCData, xnEntity} or (
      child.kind == xnElement and child.tag in inlineTags and
      not child.hasAttribute("id") and (child.attrs.isNil or child.attrs.len == 0)
    ):
      state.appendText(child, text, pendingSpace, childPath)
    else:
      flushText()
      result.add state.importNodes(child, childPath)
  flushText()

proc importNodes(
    state: var GuiImport, source: XmlNode, path: string
): seq[ViewNodeResource] =
  if source.kind != xnElement:
    return
  if source.tag == "document":
    return state.importChildren(source, path)
  if source.tag == "nk-main":
    if state.viewDepth != 0 or state.documentDepth != 0 or state.importingWindow:
      state.error("gui.document.nested", "nk-main must be the document root", path)
      return
    if not source.attrs.isNil and source.attrs.len > 0:
      state.error(
        "gui.document.attributes", "put GUI settings on windows or content views", path
      )
    inc state.documentDepth
    result = state.importChildren(source, path)
    dec state.documentDepth
    return
  if source.tag == "nk-window":
    return state.importWindow(source, path)
  let kind = state.viewKind(source, path)
  if kind.len == 0:
    return
  if state.registry.findViewKindDescriptor(kind).isNone:
    state.error("gui.kind.unregistered", "unregistered GUI kind: " & kind, path)
    return
  let id =
    if source.hasAttribute("id"):
      resourceId(source.attribute("id"))
    else:
      state.nextId("view")
  var view = initViewNodeResource(id, kind)
  if kind == "stackView":
    view.put("orientation", resourceValue("laVertical"))
  state.configureElement(source, view, path)
  state.configureAttributes(source, view, path)
  if state.registry.contentKind(kind) == gckChildren:
    inc state.viewDepth
    view.children = state.importChildren(source, path)
    dec state.viewDepth
  result.add view

proc importWindow(
    state: var GuiImport, source: XmlNode, path: string
): seq[ViewNodeResource] =
  if state.viewDepth != 0 or state.importingWindow:
    state.error(
      "gui.window.nested", "windows must be separate top-level resources", path
    )
    return
  let id = resourceId(source.attribute("id"))
  if id.isEmpty:
    state.error("gui.window.idMissing", "window requires an id", path)
  var window = WindowResource(
    id: id,
    title: resourceText(source.attribute("title")),
    frame: rect(100, 100, 640, 480),
  )
  if not source.attrs.isNil:
    for name, value in source.attrs.pairs:
      case name.toLowerAscii()
      of "id", "title":
        discard
      of "data-frame":
        try:
          window.frame = htmlRect(value)
        except ValueError as exception:
          state.error("gui.attribute.invalid", exception.msg, path & "/@data-frame", id)
      else:
        state.error(
          "gui.attribute.unsupported",
          "unsupported window attribute: " & name,
          path & "/@" & name,
          id,
        )
  state.importingWindow = true
  let content = state.importChildren(source, path)
  state.importingWindow = false
  if content.len != 1:
    state.error(
      "gui.window.content", "nk-window requires exactly one content view", path, id
    )
    return
  window.contentViewId = content[0].id
  state.loaded.bundle.windows.add window
  result = content

proc parseGuiResourceBundle*(
    source: string, registry: ResourceRegistry, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Parses GUI markup without constructing objects or loading image assets.
  ## An `nk-main` document can contain multiple `nk-window` resources, each with
  ## one content root. Use `nk-view` for a plain view, `nk-stack-view` for arranged
  ## children, and `nk-box` or `nk-group` for a titled group with one content root.
  ## View and window fragments are also supported. Browser document elements and
  ## forms are unsupported.
  ## Built-in widget tags use `nk-` plus their kind in kebab case. Application
  ## widgets use their full hyphenated registry name, such as `some-app-widget`.
  ## An optional `<!doctype nimkit>` identifies the format without a DTD.
  ## `id` names resources, `class` supplies CSS classes, and `data-kind` on `nk-view`
  ## explicitly selects a registered widget. Other `data-*` names match properties using
  ## kebab case, for example `data-edge-insets="12 24"` and `data-axis="vertical"`.
  ## Recoverable stdlib parser errors are warnings; unsupported GUI syntax and
  ## invalid property values are errors. Inspect `loaded` before construction.
  let prepared = prepareHtml(source, limits)
  result.bundle = initResourceBundle()
  result.diagnostics = prepared.diagnostics
  if result.diagnostics.hasErrors:
    return
  var errors: seq[string]
  let tree = parseHtml(newStringStream(prepared.source), "GUI markup", errors)
  for message in errors:
    result.diagnostics.add(rdsWarning, "gui.parse.recovered", message)
  var state =
    GuiImport(registry: registry, loaded: result, identifiers: prepared.identifiers)
  state.loaded.bundle.views = state.importNodes(tree, "gui")
  if state.loaded.bundle.views.len == 0:
    state.error("gui.views.missing", "markup contains no GUI views", "gui")
  var options = initResourceValidationOptions()
  options.checkFileAssets = false
  options.limits = limits
  let diagnostics = state.loaded.bundle.validateResources(registry, options)
  state.loaded.diagnostics.entries.add diagnostics.entries
  result = move state.loaded

proc parseGuiResourceBundle*(
    source: string, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Parses GUI markup with the built-in NimKit resource registry.
  parseGuiResourceBundle(source, initNimKitResourceRegistry(), limits)

proc loadGuiResourceBundle*(
    path: string, registry: ResourceRegistry, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Reads GUI markup. Filesystem failures raise `IOError` or `OSError`.
  ## Resolve relative image paths using `assetBasePath = path.parentDir` when
  ## instantiating the resulting bundle.
  if getFileSize(path) > limits.maximumDataBytes:
    result.bundle = initResourceBundle()
    result.diagnostics.add(
      rdsError, "gui.data.tooLarge", "GUI markup exceeds the byte limit", path = path
    )
  else:
    result = parseGuiResourceBundle(readFile(path), registry, limits)

proc loadGuiResourceBundle*(
    path: string, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Loads GUI markup with the built-in NimKit resource registry.
  loadGuiResourceBundle(path, initNimKitResourceRegistry(), limits)
