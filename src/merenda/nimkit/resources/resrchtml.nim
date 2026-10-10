## Import an HTML5 GUI subset as ordinary, editable NimKit resource records.
##
## HTML elements describe widgets and their children; `data-*` attributes describe
## native properties. Parsing creates no views or windows. Call `instantiateResources`
## on a successfully loaded bundle to construct the interface.

import
  std/[algorithm, htmlparser, options, os, sets, streams, strtabs, strutils, xmltree]

import ../foundation/types
import ../themes/themecore
import ./[resrccore, resrcregistry, resrcvalidation]
import ./private/[htmlsyntax, htmlvalues]

type HtmlImport = object
  registry: ResourceRegistry
  loaded: ResourceLoadResult
  identifiers: HashSet[string]
  nextIdentifier: int
  title: string

const
  containerTags = [
    "body", "main", "section", "article", "aside", "header", "footer", "nav", "div",
    "form", "figure", "ul", "ol", "li",
  ]
  inlineTags = [
    "span", "strong", "em", "b", "i", "small", "mark", "code", "kbd", "samp", "sub",
    "sup", "time", "abbr", "br",
  ]
  windowAttributes = ["data-window", "data-window-title", "data-window-frame"]

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

proc nextId(state: var HtmlImport, kind: string): ResourceId =
  while true:
    inc state.nextIdentifier
    let name = "html." & kind & "." & $state.nextIdentifier
    if name notin state.identifiers:
      state.identifiers.incl name
      return resourceId(name)

proc error(state: var HtmlImport, code, message, path: string, id = resourceId("")) =
  state.loaded.diagnostics.add(rdsError, code, message, path = path, resourceId = id)

proc put(node: var ViewNodeResource, name: string, value: ResourceValue) =
  for property in node.properties.mitems:
    if property.name == name:
      property.value = value
      return
  node.properties.add resourceProperty(name, value)

proc putAttribute(
    state: var HtmlImport, view: var ViewNodeResource, name, value, path: string
) =
  let key = name.attributeKey()
  for descriptor in state.registry.viewProperties(view.kind):
    if descriptor.name.attributeKey() == key:
      try:
        view.put(descriptor.name, htmlValue(value, descriptor))
      except ValueError as exception:
        state.error("html.attribute.invalid", exception.msg, path, view.id)
      return
  state.error(
    "html.attribute.unsupported",
    "property '" & name & "' is not registered for " & view.kind,
    path,
    view.id,
  )

proc appendText(
    state: var HtmlImport,
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
    elif node.tag in inlineTags or
        node.tag in [
          "label", "p", "h1", "h2", "h3", "h4", "h5", "h6", "button", "option", "title",
          "legend", "output", "figcaption",
        ]:
      for child in node:
        state.appendText(child, text, pendingSpace, path)
    else:
      state.error(
        "html.element.unsupportedChild",
        "<" & node.tag & "> cannot appear inside text content",
        path,
      )
  else:
    discard

proc textContent(state: var HtmlImport, node: XmlNode, path: string): string =
  var pendingSpace: bool
  state.appendText(node, result, pendingSpace, path)

proc isContainer(node: XmlNode): bool =
  if node.tag in containerTags:
    return true
  if node.tag == "label":
    for child in node:
      if child.kind == xnElement and child.tag notin inlineTags:
        return true

proc viewKind(state: var HtmlImport, node: XmlNode, path: string): string =
  if node.hasAttribute("data-kind"):
    return node.attribute("data-kind")
  if node.isContainer():
    return "stackView"
  if node.tag in inlineTags:
    return "label"
  case node.tag
  of "button":
    "button"
  of "label", "p", "span", "h1", "h2", "h3", "h4", "h5", "h6", "output", "figcaption":
    "label"
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
    of "button", "submit", "reset":
      "button"
    else:
      state.error(
        "html.input.unsupported",
        "unsupported input type: " & node.attribute("type"),
        path,
      )
      ""
  else:
    state.error(
      "html.element.unsupported", "unsupported GUI element <" & node.tag & ">", path
    )
    ""

proc configureSelect(
    state: var HtmlImport, source: XmlNode, view: var ViewNodeResource, path: string
) =
  var
    titles, values: seq[string]
    selected = 0
    selectionSeen: bool
  if source.hasAttribute("multiple"):
    state.error(
      "html.select.multiple", "select supports a single selection", path, view.id
    )
  for child in source:
    if child.kind == xnElement:
      if child.tag != "option":
        state.error(
          "html.element.unsupportedChild", "select requires option children", path,
          view.id,
        )
      else:
        let text = state.textContent(child, path)
        titles.add child.attribute("label", text)
        values.add child.attribute("value", text)
        if child.hasAttribute("disabled"):
          state.error(
            "html.option.disabled", "disabled options are not supported", path, view.id
          )
        if child.hasAttribute("selected"):
          if selectionSeen:
            state.error(
              "html.select.selection", "select has more than one selected option", path,
              view.id,
            )
          selected = titles.high
          selectionSeen = true
  view.put("editable", resourceValue(false))
  view.put("items", resourceValue(titles))
  view.put("itemValues", resourceValue(values))
  view.put("selectedIndex", resourceValue(if titles.len == 0: -1 else: selected))

proc configureElement(
    state: var HtmlImport, source: XmlNode, view: var ViewNodeResource, path: string
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
    of "button", "submit", "reset":
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
      state.error("html.image.sourceMissing", "img requires src", path, view.id)
    else:
      let id = state.nextId("image")
      state.loaded.bundle.images.add ImageAssetResource(
        id: id, sourceKind: risFile, path: src
      )
      view.put("image", resourceValue(resourceReference(rrImage, id)))
    if source.hasAttribute("alt"):
      view.put("toolTip", resourceValue(source.attribute("alt")))
  else:
    if view.kind == "label":
      if source.tag in ["h1", "h2", "h3", "h4", "h5", "h6"]:
        state.putAttribute(
          view, "labelStyle", if source.tag == "h1": "title" else: "heading", path
        )
      view.put("stringValue", resourceValue(state.textContent(source, path)))

proc comboAttributeOrder(name: string): int =
  case attributeKey(name)
  of "dataitems": 0
  of "dataitemvalues": 1
  else: 2

proc configureAttributes(
    state: var HtmlImport, source: XmlNode, view: var ViewNodeResource, path: string
) =
  if source.hasAttribute("id"):
    view.put("styleId", resourceValue(source.attribute("id")))
  if source.hasAttribute("title"):
    view.put("toolTip", resourceValue(source.attribute("title")))
  if source.hasAttribute("hidden"):
    view.put("hidden", resourceValue(true))
  if source.hasAttribute("disabled"):
    if view.kind == "textView":
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
  if view.kind == "comboBox":
    # Setting items recreates options, so values and selection must follow it.
    attributes.sort do(left, right: string) -> int:
      result = cmp(comboAttributeOrder(left), comboAttributeOrder(right))
      if result == 0:
        result = cmp(left, right)
  else:
    attributes.sort()
  for originalName in attributes:
    let
      name = originalName.toLowerAscii()
      value = source.attrs[originalName]
      attributePath = path & "/@" & name
    if name.startsWith("data-") and name notin windowAttributes and name != "data-kind":
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
        "html.attribute.unsupported",
        "use native data-* properties or wire behavior in Nim", attributePath, view.id,
      )

  if source.hasAttribute("class") and not source.hasAttribute("data-style-classes"):
    var classes: seq[string]
    if view.kind == "label":
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
  state: var HtmlImport, source: XmlNode, path: string
): seq[ViewNodeResource]

proc importChildren(
    state: var HtmlImport, source: XmlNode, path: string
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
    state: var HtmlImport, source: XmlNode, path: string
): seq[ViewNodeResource] =
  if source.kind != xnElement:
    return
  if source.tag in ["document", "html"]:
    return state.importChildren(source, path)
  if source.tag == "head":
    for child in source:
      if child.kind == xnElement:
        if child.tag == "title":
          state.title = state.textContent(child, path & "/title")
        elif child.tag != "meta":
          state.error(
            "html.element.unsupported",
            "unsupported head element <" & child.tag & ">",
            path,
          )
    return
  let kind = state.viewKind(source, path)
  if kind.len == 0:
    return
  if state.registry.findViewKindDescriptor(kind).isNone:
    state.error("html.kind.unregistered", "unregistered GUI kind: " & kind, path)
    return
  let id =
    if source.hasAttribute("id"):
      resourceId(source.attribute("id"))
    else:
      state.nextId("view")
  var view = initViewNodeResource(id, kind)
  if kind == "stackView":
    view.put(
      "orientation",
      resourceValue(
        if source.tag in ["nav", "label"]: "laHorizontal" else: "laVertical"
      ),
    )
  state.configureElement(source, view, path)
  state.configureAttributes(source, view, path)
  if source.isContainer() or (
    source.hasAttribute("data-kind") and
    source.tag notin [
      "button", "input", "img", "progress", "select", "textarea", "p", "span", "h1",
      "h2", "h3", "h4", "h5", "h6", "output", "figcaption",
    ]
  ):
    view.children = state.importChildren(source, path)

  if source.hasAttribute("data-window"):
    var window = WindowResource(
      id: resourceId(source.attribute("data-window")),
      title: resourceText(source.attribute("data-window-title", state.title)),
      frame: rect(100, 100, 640, 480),
      contentViewId: view.id,
    )
    if source.hasAttribute("data-window-frame"):
      try:
        window.frame = htmlRect(source.attribute("data-window-frame"))
      except ValueError as exception:
        state.error(
          "html.attribute.invalid",
          exception.msg,
          path & "/@data-window-frame",
          window.id,
        )
    state.loaded.bundle.windows.add window
  elif source.hasAttribute("data-window-title") or
      source.hasAttribute("data-window-frame"):
    state.error(
      "html.window.missing", "window attributes require data-window", path, view.id
    )
  result.add view

proc parseHtmlResourceBundle*(
    source: string, registry: ResourceRegistry, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Parses HTML without constructing GUI objects or loading image assets.
  ## `id` names resources, `class` supplies CSS classes, and `data-kind` selects a
  ## registered native widget. Other `data-*` names match native properties using
  ## kebab case, for example `data-edge-insets="12 24"` and `data-axis="vertical"`.
  ## Recoverable stdlib parser errors are warnings; unsupported GUI syntax and
  ## invalid property values are errors. Inspect `loaded` before construction.
  let prepared = prepareHtml(source, limits)
  result.bundle = initResourceBundle()
  result.diagnostics = prepared.diagnostics
  if result.diagnostics.hasErrors:
    return
  var errors: seq[string]
  let tree = parseHtml(newStringStream(prepared.source), "HTML", errors)
  for message in errors:
    result.diagnostics.add(rdsWarning, "html.parse.recovered", message)
  var state =
    HtmlImport(registry: registry, loaded: result, identifiers: prepared.identifiers)
  state.loaded.bundle.views = state.importNodes(tree, "html")
  if state.loaded.bundle.views.len == 0:
    state.error("html.views.missing", "HTML contains no GUI views", "html")
  var options = initResourceValidationOptions()
  options.checkFileAssets = false
  options.limits = limits
  let diagnostics = state.loaded.bundle.validateResources(registry, options)
  state.loaded.diagnostics.entries.add diagnostics.entries
  result = move state.loaded

proc parseHtmlResourceBundle*(
    source: string, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Parses an HTML interface with the built-in NimKit resource registry.
  parseHtmlResourceBundle(source, initNimKitResourceRegistry(), limits)

proc loadHtmlResourceBundle*(
    path: string, registry: ResourceRegistry, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Reads an HTML interface. Filesystem failures raise `IOError` or `OSError`.
  ## Resolve relative image paths using `assetBasePath = path.parentDir` when
  ## instantiating the resulting bundle.
  if getFileSize(path) > limits.maximumDataBytes:
    result.bundle = initResourceBundle()
    result.diagnostics.add(
      rdsError, "html.data.tooLarge", "HTML exceeds the byte limit", path = path
    )
  else:
    result = parseHtmlResourceBundle(readFile(path), registry, limits)

proc loadHtmlResourceBundle*(
    path: string, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Loads an HTML interface with the built-in NimKit resource registry.
  loadHtmlResourceBundle(path, initNimKitResourceRegistry(), limits)
