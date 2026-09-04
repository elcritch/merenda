## Persisted configuration for the standalone Kosmo editor.

import std/[json, jsonutils, os]

type KosmoConfig* = object
  ## User-configurable appearance choices persisted by the standalone editor.
  moeTheme*: string
  merendaTheme*: string
  merendaFont*: string
  merendaMonoFont*: string
  merendaFontSize*: float32

func defaultKosmoConfigPath*(): string =
  ## Return the standalone editor's JSON configuration file path.
  getConfigDir() / "kosmo" / "config.json"

proc loadKosmoConfig*(path: string): KosmoConfig =
  ## Load a JSON configuration file, returning defaults when it is absent or invalid.
  if path.len == 0 or not fileExists(path):
    return
  try:
    result = jsonTo(parseJson(readFile(path)), KosmoConfig)
  except CatchableError:
    discard

proc saveKosmoConfig*(config: KosmoConfig, path: string): bool =
  ## Write `config` as JSON, creating its parent directory when needed.
  if path.len == 0:
    return
  try:
    createDir(path.parentDir())
    writeFile(path, config.toJson().pretty())
    result = true
  except CatchableError:
    discard
