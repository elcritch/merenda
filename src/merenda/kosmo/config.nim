## Persisted configuration for the standalone Kosmo editor.

import std/[json, jsonutils, os]

import ../nimkit/foundation/atomicfiles

const DefaultKosmoFileTreeIndentation* = 10.0'f32

type KosmoConfig* = object ## User choices persisted by the standalone editor.
  moeTheme*: string
  nimLspCommand*: string
  merendaTheme*: string
  merendaFont*: string
  merendaMonoFont*: string
  merendaFontSize*: float32
  merendaInvertScrolling*: bool
  merendaUiScale*: float32
  merendaAutoSaveDefaults*: bool
  fileTreeIndentation*: float32 = DefaultKosmoFileTreeIndentation
    ## Horizontal spacing in points for each file-tree level; zero removes indentation.

func defaultKosmoConfigPath*(): string =
  ## Return the standalone editor's JSON configuration file path.
  getConfigDir() / "kosmo" / "config.json"

proc loadKosmoConfig*(path: string): KosmoConfig =
  ## Load a JSON configuration file, returning defaults when it is absent or invalid.
  result = KosmoConfig()
  if path.len == 0 or not fileExists(path):
    return
  try:
    var config = KosmoConfig()
    config.fromJson(parseJson(readFile(path)), Joptions(allowMissingKeys: true))
    result = config
  except CatchableError:
    discard

proc saveKosmoConfig*(config: KosmoConfig, path: string): bool =
  ## Atomically replace JSON configuration, creating its parent directory when needed.
  if path.len == 0:
    return
  try:
    createDir(path.parentDir())
    atomicWriteFile(path, config.toJson().pretty())
    result = true
  except CatchableError:
    discard
