## JSON customization for NimKit key binding tables.

import std/json

import ../foundation/selectors
import ./keybindings

type KeyBindingJsonResult* = object
  ## Outcome of applying a JSON command-to-shortcut map.
  applied*: int
  errors*: seq[string]

func succeeded*(outcome: KeyBindingJsonResult): bool =
  outcome.errors.len == 0

func commandAllowed(command: string, allowedCommands: openArray[string]): bool =
  if allowedCommands.len == 0:
    return true
  command in allowedCommands

proc shortcutDescriptions(
    command: string, value: JsonNode, descriptions: var seq[string]
): string =
  case value.kind
  of JString:
    descriptions.add value.getStr()
  of JArray:
    for item in value.items:
      if item.kind != JString:
        return "Key binding '" & command & "' must contain only strings"
      descriptions.add item.getStr()
  of JNull:
    discard
  else:
    return "Key binding '" & command & "' must be a string, array, or null"

proc applyKeyBindingOverrides*(
    table: var KeyBindingTable, node: JsonNode, allowedCommands: openArray[string] = []
): KeyBindingJsonResult =
  ## Apply an object mapping command names to shortcut strings or arrays.
  ##
  ## Whitespace separates the strokes in a sequence, while arrays provide
  ## alternative sequences. A listed command replaces all of its previous
  ## bindings. An empty array or `null` disables the command. Invalid entries
  ## leave that command unchanged.
  if node.kind != JObject:
    result.errors.add "Key bindings JSON must be an object"
    return

  for command, value in node.pairs:
    if command.len == 0:
      result.errors.add "Key binding command names cannot be empty"
    elif not command.commandAllowed(allowedCommands):
      result.errors.add "Unknown key binding command '" & command & "'"
    else:
      var descriptions: seq[string]
      let descriptionError = command.shortcutDescriptions(value, descriptions)
      if descriptionError.len > 0:
        result.errors.add descriptionError
      else:
        var sequences: seq[KeySequence]
        var parseError = ""
        for description in descriptions:
          if parseError.len == 0:
            try:
              sequences.add parseKeySequence(description)
            except ValueError as error:
              parseError = "Invalid shortcut for '" & command & "': " & error.msg
        if parseError.len > 0:
          result.errors.add parseError
        else:
          let selector = actionSelector(command)
          var updated: KeyBindingTable
          try:
            for binding in table.bindings:
              if binding.selector != selector:
                updated.add(binding.sequence, binding.selector)
            for sequence in sequences:
              updated.add(sequence, selector)
            table = move updated
            inc result.applied
          except ValueError as error:
            result.errors.add "Invalid shortcut for '" & command & "': " & error.msg

proc applyKeyBindingOverridesJson*(
    table: var KeyBindingTable,
    jsonText: string,
    allowedCommands: openArray[string] = [],
): KeyBindingJsonResult =
  ## Parse and apply a JSON command-to-shortcut map.
  try:
    result = table.applyKeyBindingOverrides(parseJson(jsonText), allowedCommands)
  except JsonParsingError as error:
    result.errors.add "Invalid key bindings JSON: " & error.msg

proc loadKeyBindingOverridesJson*(
    table: var KeyBindingTable, path: string, allowedCommands: openArray[string] = []
): KeyBindingJsonResult =
  ## Read and apply a JSON command-to-shortcut map from `path`.
  try:
    result = table.applyKeyBindingOverridesJson(readFile(path), allowedCommands)
  except IOError as error:
    result.errors.add "Could not read key bindings from '" & path & "': " & error.msg
