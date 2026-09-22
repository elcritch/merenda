## Discovery, validation, and installation of built-in VS Code TextMate grammars.

import std/[algorithm, json, options, os, sets, strutils, tables, tempfiles]

import crunchy/[common, sha256]
import matter/rawgrammar
import sigils/core
import ../nimkit as nimkit

const
  KosmoVscodeGrammarDirectoryName* = "grammars"
  KosmoVscodeGrammarMetadataName = "kosmo-grammar.json"
  KosmoVscodeGrammarMaximumBytes* = 4 * 1024 * 1024

type
  VscodeGrammarFile* = object
    path*: string
    scopeName*: string
    languageId*: string

  VscodeGrammarCandidate* = object
    id*: string
    name*: string
    extensionFolder*: string
    languageId*: string
    scopeName*: string
    rootPath*: string
    sourceCommit*: string
    extensions*: seq[string]
    fileNames*: seq[string]
    grammarFiles*: seq[VscodeGrammarFile]

  InstalledVscodeGrammar* = object
    candidate*: VscodeGrammarCandidate
    directory*: string
    sources*: seq[tuple[path, content, scopeName, languageId: string]]

  VscodeGrammarAssetKind = enum
    vgakTree
    vgakManifest
    vgakGrammar

  VscodeGrammarAssetRequest = object
    kind: VscodeGrammarAssetKind
    extensionFolder: string
    path: string

  KosmoVscodeGrammarCatalog* = ref object of Agent
    loader: nimkit.UrlAssetLoader
    pending: Table[uint64, VscodeGrammarAssetRequest]
    tree: VscodeGrammarTree
    allCandidates: seq[VscodeGrammarCandidate]
    candidates: seq[VscodeGrammarCandidate]
    query: string
    status: string
    catalogLoading: bool
    catalogReady: bool
    manifestsLoaded: int
    manifestsTotal: int
    failedManifests: int
    installing: Option[VscodeGrammarCandidate]
    installContents: Table[string, string]
    installRemaining: int
    closed: bool

  VscodeGrammarTree* = object
    sha*: string
    paths: HashSet[string]
    extensionFolders*: seq[string]

func defaultKosmoVscodeGrammarDirectory*(): string =
  ## Return Kosmo's user configuration folder for installed grammars.
  getConfigDir() / "kosmo" / KosmoVscodeGrammarDirectoryName

proc validCommitSha(value: string): bool =
  if value.len != 40:
    return
  for character in value:
    if character notin {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
      return
  true

proc validExtensionFolder(value: string): bool =
  if value.len == 0 or value in [".", ".."]:
    return
  for character in value:
    if not (character.isAlphaNumeric or character in {'.', '-', '_'}) or
        ord(character) > 127:
      return
  true

proc safeRelativeGrammarPath(value: string): string =
  if value.len == 0 or '\\' in value or '\0' in value or ':' in value or '?' in value or
      '#' in value or value[0] == '/':
    raise newException(ValueError, "grammar path must be relative")
  for character in value:
    if ord(character) < 0x20:
      raise newException(ValueError, "grammar path contains a control character")
  result = value
  if result.startsWith("./"):
    result = result[2 ..^ 1]
  if result.len == 0:
    raise newException(ValueError, "grammar path cannot be empty")
  for segment in result.split('/'):
    if segment.len == 0 or segment in [".", ".."]:
      raise newException(ValueError, "grammar path contains an unsafe segment")

proc safeFileExtension(value: string): string =
  let extension = value.strip().toLowerAscii()
  if extension.len < 2 or extension[0] != '.':
    return
  for character in extension[1 ..^ 1]:
    if not (character.isAlphaNumeric or character in {'.', '+', '-', '_'}) or
        ord(character) > 127:
      return
  extension

proc safeFileName(value: string): string =
  let name = value.strip()
  if name.len == 0 or name in [".", ".."] or '/' in name or '\\' in name or '\0' in name:
    return
  name

proc jsonString(node: JsonNode, key: string): string =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JString:
    result = node[key].getStr()

proc jsonStrings(node: JsonNode, key: string): seq[string] =
  if node.kind != JObject or not node.hasKey(key) or node[key].kind != JArray:
    return
  for value in node[key]:
    if value.kind == JString and value.getStr().len > 0:
      result.add value.getStr()

proc parseVscodeGrammarTree*(content: string): VscodeGrammarTree =
  ## Parse GitHub's recursive VS Code tree and retain safe in-repository paths.
  let tree = parseJson(content)
  result.sha = tree.jsonString("sha")
  if not result.sha.validCommitSha():
    raise newException(ValueError, "VS Code tree has an invalid commit SHA")
  if tree.hasKey("truncated") and tree["truncated"].kind == JBool and
      tree["truncated"].getBool():
    raise newException(ValueError, "VS Code grammar catalog was truncated")
  if not tree.hasKey("tree") or tree["tree"].kind != JArray:
    raise newException(ValueError, "VS Code tree has no file list")

  result.paths = initHashSet[string]()
  var folders = initHashSet[string]()
  var manifestFolders = initHashSet[string]()
  for entry in tree["tree"]:
    let path = entry.jsonString("path")
    if path.len == 0 or not entry.hasKey("type") or entry["type"].getStr() != "blob":
      continue
    result.paths.incl path
    let parts = path.split('/')
    if parts.len == 3 and parts[0] == "extensions" and parts[2] == "package.json" and
        parts[1].validExtensionFolder():
      manifestFolders.incl parts[1]
    elif parts.len >= 4 and parts[0] == "extensions" and parts[1].validExtensionFolder():
      let lowerPath = path.toLowerAscii()
      if ".tmlanguage" in lowerPath or ".tmgrammar" in lowerPath:
        folders.incl parts[1]
  for folder in folders.items:
    if folder in manifestFolders:
      result.extensionFolders.add folder
  result.extensionFolders.sort()

proc parseVscodeGrammarManifest*(
    extensionFolder, sourceCommit, content: string, tree: VscodeGrammarTree
): seq[VscodeGrammarCandidate] =
  ## Return language roots declared by one validated VS Code extension manifest.
  if not extensionFolder.validExtensionFolder() or not sourceCommit.validCommitSha():
    raise newException(ValueError, "invalid VS Code extension identity")
  let package = parseJson(content)
  if not package.hasKey("contributes") or package["contributes"].kind != JObject:
    return
  let contributions = package["contributes"]
  if not contributions.hasKey("grammars") or contributions["grammars"].kind != JArray:
    return

  var grammarFiles: seq[VscodeGrammarFile]
  var seenPaths = initHashSet[string]()
  for contribution in contributions["grammars"]:
    let
      path = contribution.jsonString("path").safeRelativeGrammarPath()
      scopeName = contribution.jsonString("scopeName")
    if scopeName.len == 0:
      continue
    let fullPath = "extensions/" & extensionFolder & "/" & path
    if fullPath notin tree.paths or path in seenPaths:
      continue
    seenPaths.incl path
    grammarFiles.add VscodeGrammarFile(
      path: path, scopeName: scopeName, languageId: contribution.jsonString("language")
    )
  if grammarFiles.len == 0:
    return

  var languages: seq[tuple[id, name: string, extensions, fileNames: seq[string]]]
  if contributions.hasKey("languages") and contributions["languages"].kind == JArray:
    for language in contributions["languages"]:
      let id = language.jsonString("id")
      if id.len == 0:
        continue
      var name = id
      let aliases = language.jsonStrings("aliases")
      if aliases.len > 0 and aliases[0].len > 0 and aliases[0][0] != '%':
        name = aliases[0]
      var extensions, fileNames: seq[string]
      for value in language.jsonStrings("extensions"):
        let extension = value.safeFileExtension()
        if extension.len > 0 and extension notin extensions:
          extensions.add extension
      for value in language.jsonStrings("filenames"):
        let fileName = value.safeFileName()
        if fileName.len > 0 and fileName notin fileNames:
          fileNames.add fileName
      languages.add (id: id, name: name, extensions: extensions, fileNames: fileNames)

  for language in languages:
    var roots: seq[VscodeGrammarFile]
    for grammar in grammarFiles:
      if grammar.languageId == language.id:
        roots.add grammar
    if roots.len == 0:
      continue
    result.add VscodeGrammarCandidate(
      id: extensionFolder & ":" & language.id,
      name: language.name,
      extensionFolder: extensionFolder,
      languageId: language.id,
      scopeName: roots[0].scopeName,
      rootPath: roots[0].path,
      sourceCommit: sourceCommit,
      extensions: language.extensions,
      fileNames: language.fileNames,
      grammarFiles: grammarFiles,
    )

proc normalizedSearchText(value: string): string =
  for character in value.toLowerAscii():
    if character.isAlphaNumeric and ord(character) < 128:
      result.add character

proc matchesVscodeGrammarQuery*(
    candidate: VscodeGrammarCandidate, query: string
): bool =
  let
    rawQuery = query.strip().toLowerAscii()
    compactQuery = rawQuery.normalizedSearchText()
  if compactQuery.len == 0:
    return false
  var fields =
    @[
      candidate.name, candidate.extensionFolder, candidate.languageId,
      candidate.scopeName,
    ]
  fields.add candidate.extensions
  fields.add candidate.fileNames
  for field in fields:
    let normalized = field.toLowerAscii()
    if rawQuery in normalized or compactQuery in normalized.normalizedSearchText():
      return true

proc candidateDirectoryName(candidate: VscodeGrammarCandidate): string =
  var stem: string
  for character in candidate.extensionFolder & "-" & candidate.languageId:
    if character.isAlphaNumeric and ord(character) < 128:
      stem.add character.toLowerAscii()
    elif stem.len > 0 and stem[^1] != '-':
      stem.add '-'
  stem = stem.strip(chars = {'-'})
  if stem.len == 0:
    stem = "language"
  stem & "-" & sha256(candidate.id).toHex()[0 .. 11]

proc metadataJson(candidate: VscodeGrammarCandidate): JsonNode =
  result = newJObject()
  result["id"] = %candidate.id
  result["name"] = %candidate.name
  result["extensionFolder"] = %candidate.extensionFolder
  result["languageId"] = %candidate.languageId
  result["scopeName"] = %candidate.scopeName
  result["rootPath"] = %candidate.rootPath
  result["sourceCommit"] = %candidate.sourceCommit
  result["extensions"] = %candidate.extensions
  result["fileNames"] = %candidate.fileNames
  result["grammarFiles"] = newJArray()
  for grammar in candidate.grammarFiles:
    result["grammarFiles"].add(
      %*{
        "path": grammar.path,
        "scopeName": grammar.scopeName,
        "languageId": grammar.languageId,
      }
    )

proc parseCandidateMetadata(node: JsonNode): VscodeGrammarCandidate =
  result.id = node.jsonString("id")
  result.name = node.jsonString("name")
  result.extensionFolder = node.jsonString("extensionFolder")
  result.languageId = node.jsonString("languageId")
  result.scopeName = node.jsonString("scopeName")
  result.rootPath = node.jsonString("rootPath")
  result.sourceCommit = node.jsonString("sourceCommit")
  result.extensions = node.jsonStrings("extensions")
  result.fileNames = node.jsonStrings("fileNames")
  if not node.hasKey("grammarFiles") or node["grammarFiles"].kind != JArray:
    raise newException(ValueError, "installed grammar metadata has no grammar files")
  for value in node["grammarFiles"]:
    result.grammarFiles.add VscodeGrammarFile(
      path: value.jsonString("path").safeRelativeGrammarPath(),
      scopeName: value.jsonString("scopeName"),
      languageId: value.jsonString("languageId"),
    )
  if result.id.len == 0 or result.name.len == 0 or result.scopeName.len == 0 or
      not result.extensionFolder.validExtensionFolder() or
      not result.sourceCommit.validCommitSha() or
      result.rootPath.safeRelativeGrammarPath() != result.rootPath:
    raise newException(ValueError, "installed grammar metadata is invalid")

proc validateVscodeGrammarFiles*(
    candidate: VscodeGrammarCandidate, contents: Table[string, string]
) =
  ## Parse every declared grammar and verify its scope before installation.
  if candidate.grammarFiles.len == 0 or candidate.rootPath.len == 0:
    raise newException(ValueError, "VS Code language has no TextMate grammar files")
  if candidate.grammarFiles.len > 32:
    raise newException(ValueError, "VS Code language declares too many grammar files")
  var rootFound: bool
  var totalBytes: int
  for file in candidate.grammarFiles:
    let relativePath = file.path.safeRelativeGrammarPath()
    if relativePath == KosmoVscodeGrammarMetadataName:
      raise newException(ValueError, "grammar path conflicts with Kosmo metadata")
    if not contents.hasKey(relativePath):
      raise newException(ValueError, "missing downloaded grammar: " & relativePath)
    let source = contents[relativePath]
    if source.len > KosmoVscodeGrammarMaximumBytes:
      raise newException(ValueError, "grammar exceeds the 4 MiB safety limit")
    totalBytes += source.len
    if totalBytes > 16 * 1024 * 1024:
      raise newException(ValueError, "language grammars exceed the 16 MiB safety limit")
    let raw = parseRawGrammar(source, relativePath)
    if file.scopeName.len == 0 or raw.scopeName != file.scopeName:
      raise newException(
        ValueError, "grammar scope does not match the VS Code manifest: " & relativePath
      )
    if relativePath == candidate.rootPath and file.languageId == candidate.languageId:
      rootFound = true
  if not rootFound:
    raise newException(ValueError, "VS Code language root grammar was not found")

proc installVscodeGrammar*(
    candidate: VscodeGrammarCandidate,
    contents: Table[string, string],
    grammarDirectory = defaultKosmoVscodeGrammarDirectory(),
): string =
  ## Validate and atomically install one VS Code language package under Kosmo config.
  candidate.validateVscodeGrammarFiles(contents)
  if not candidate.extensionFolder.validExtensionFolder() or
      not candidate.sourceCommit.validCommitSha():
    raise newException(ValueError, "invalid VS Code grammar package identity")

  createDir(grammarDirectory)
  let
    destination = grammarDirectory / candidate.candidateDirectoryName()
    staging = createTempDir(".kosmo-grammar-", ".tmp", grammarDirectory)
  if dirExists(destination):
    removeDir(staging)
    raise newException(ValueError, "this VS Code grammar is already installed")
  try:
    for file in candidate.grammarFiles:
      let path = staging / file.path.safeRelativeGrammarPath()
      createDir(path.parentDir())
      writeFile(path, contents[file.path])
    writeFile(
      staging / KosmoVscodeGrammarMetadataName, candidate.metadataJson().pretty()
    )
    moveDir(staging, destination)
    result = destination
  finally:
    if dirExists(staging):
      removeDir(staging)

proc installedVscodeGrammars*(
    grammarDirectory = defaultKosmoVscodeGrammarDirectory()
): seq[InstalledVscodeGrammar] =
  ## Read, revalidate, and return grammars already installed for this user.
  if not dirExists(grammarDirectory):
    return
  for kind, directory in walkDir(grammarDirectory):
    if kind != pcDir:
      continue
    try:
      let metadataPath = directory / KosmoVscodeGrammarMetadataName
      if not fileExists(metadataPath) or getFileSize(metadataPath) > 256 * 1024:
        continue
      let candidate = parseCandidateMetadata(parseJson(readFile(metadataPath)))
      var contents = initTable[string, string]()
      var installed = InstalledVscodeGrammar(candidate: candidate, directory: directory)
      for file in candidate.grammarFiles:
        let path = directory / file.path.safeRelativeGrammarPath()
        if not fileExists(path) or getFileSize(path) > KosmoVscodeGrammarMaximumBytes:
          raise
            newException(ValueError, "installed grammar file is missing or too large")
        let content = readFile(path)
        contents[file.path] = content
        installed.sources.add (
          path: path,
          content: content,
          scopeName: file.scopeName,
          languageId: file.languageId,
        )
      candidate.validateVscodeGrammarFiles(contents)
      result.add move installed
    except CatchableError:
      discard
  result.sort do(left, right: InstalledVscodeGrammar) -> int:
    result = cmpIgnoreCase(left.candidate.name, right.candidate.name)
    if result == 0:
      result = cmp(left.candidate.id, right.candidate.id)

proc isVscodeGrammarInstalled*(
    candidateId: string, grammarDirectory = defaultKosmoVscodeGrammarDirectory()
): bool =
  ## Check package metadata without parsing grammar files on each UI selection.
  if not dirExists(grammarDirectory):
    return
  for kind, directory in walkDir(grammarDirectory):
    if kind != pcDir:
      continue
    try:
      let metadataPath = directory / KosmoVscodeGrammarMetadataName
      if not fileExists(metadataPath) or getFileSize(metadataPath) > 256 * 1024:
        continue
      if parseCandidateMetadata(parseJson(readFile(metadataPath))).id == candidateId:
        return true
    except CatchableError:
      discard

const
  VscodeRepositoryTreeUrl =
    "https://api.github.com/repos/microsoft/vscode/git/trees/main?recursive=1"
  VscodeRawContentBase = "https://raw.githubusercontent.com/microsoft/vscode/"
  VscodeCatalogMaximumBytes = 32 * 1024 * 1024

proc vscodeGrammarCatalogDidUpdate*(catalog: KosmoVscodeGrammarCatalog) {.signal.}
proc vscodeGrammarDidInstall*(
  catalog: KosmoVscodeGrammarCatalog, directory: string
) {.signal.}

proc processAsset(
  catalog: KosmoVscodeGrammarCatalog,
  request: VscodeGrammarAssetRequest,
  url, path: string,
  errorMessage = "",
)

proc requestAsset(
    catalog: KosmoVscodeGrammarCatalog, url: string, request: VscodeGrammarAssetRequest
) =
  if catalog.closed or catalog.loader.isNil:
    return
  let cachedPath = catalog.loader.cachedAssetPath(url)
  if fileExists(cachedPath):
    catalog.processAsset(request, url, cachedPath)
    return
  let handle = catalog.loader.load(url)
  if handle.isFinished():
    if handle.succeeded():
      catalog.processAsset(request, url, handle.result().path)
    else:
      catalog.processAsset(request, url, "", handle.result().errorMessage)
  else:
    catalog.pending[handle.identifier()] = request

proc grammarUrl(commit, extensionFolder, path: string): string =
  VscodeRawContentBase & commit & "/extensions/" & extensionFolder & "/" & path

proc finishCatalogSearch(catalog: KosmoVscodeGrammarCatalog) =
  catalog.catalogLoading = false
  catalog.catalogReady = true
  catalog.tree = default(VscodeGrammarTree)
  catalog.candidates.setLen(0)
  for candidate in catalog.allCandidates:
    if candidate.matchesVscodeGrammarQuery(catalog.query):
      catalog.candidates.add candidate
  catalog.candidates.sort do(left, right: VscodeGrammarCandidate) -> int:
    result = cmpIgnoreCase(left.name, right.name)
    if result == 0:
      result = cmp(left.id, right.id)
  catalog.status =
    if catalog.candidates.len == 0:
      "No matching built-in VS Code grammars found."
    else:
      $catalog.candidates.len & " VS Code language grammars found."
  if catalog.failedManifests > 0:
    catalog.status.add(
      " " & $catalog.failedManifests & " extension manifests could not be read."
    )
  emit catalog.vscodeGrammarCatalogDidUpdate()

proc finishGrammarInstall(catalog: KosmoVscodeGrammarCatalog) =
  if catalog.installing.isNone:
    return
  let candidate = catalog.installing.get()
  try:
    let directory = installVscodeGrammar(candidate, catalog.installContents)
    catalog.status = "Installed " & candidate.name & " (" & candidate.scopeName & ")."
    catalog.installing = none(VscodeGrammarCandidate)
    catalog.installContents.clear()
    catalog.installRemaining = 0
    emit catalog.vscodeGrammarDidInstall(directory)
    emit catalog.vscodeGrammarCatalogDidUpdate()
  except CatchableError as error:
    catalog.status = "Could not install " & candidate.name & ": " & error.msg
    catalog.installing = none(VscodeGrammarCandidate)
    catalog.installContents.clear()
    catalog.installRemaining = 0
    emit catalog.vscodeGrammarCatalogDidUpdate()

proc processAsset(
    catalog: KosmoVscodeGrammarCatalog,
    request: VscodeGrammarAssetRequest,
    url, path, errorMessage: string,
) =
  if catalog.closed:
    return
  if errorMessage.len > 0 or path.len == 0:
    case request.kind
    of vgakTree:
      catalog.catalogLoading = false
      catalog.status = "Could not load the VS Code language catalog: " & errorMessage
      emit catalog.vscodeGrammarCatalogDidUpdate()
    of vgakManifest:
      inc catalog.manifestsLoaded
      inc catalog.failedManifests
      if catalog.manifestsLoaded >= catalog.manifestsTotal:
        catalog.finishCatalogSearch()
      else:
        catalog.status =
          "Loading VS Code language metadata (" & $catalog.manifestsLoaded & " of " &
          $catalog.manifestsTotal & ")."
        emit catalog.vscodeGrammarCatalogDidUpdate()
    of vgakGrammar:
      catalog.status =
        "Could not download grammar file: " & request.path &
        (if errorMessage.len > 0: " (" & errorMessage & ")" else: "")
      catalog.installing = none(VscodeGrammarCandidate)
      catalog.installContents.clear()
      catalog.installRemaining = 0
      emit catalog.vscodeGrammarCatalogDidUpdate()
    return

  case request.kind
  of vgakTree:
    try:
      catalog.tree = parseVscodeGrammarTree(readFile(path))
      catalog.manifestsLoaded = 0
      catalog.manifestsTotal = catalog.tree.extensionFolders.len
      catalog.failedManifests = 0
      catalog.status =
        "Loading VS Code language metadata (0 of " & $catalog.manifestsTotal & ")."
      emit catalog.vscodeGrammarCatalogDidUpdate()
      if catalog.manifestsTotal == 0:
        catalog.finishCatalogSearch()
      else:
        for folder in catalog.tree.extensionFolders:
          catalog.requestAsset(
            grammarUrl(catalog.tree.sha, folder, "package.json"),
            VscodeGrammarAssetRequest(kind: vgakManifest, extensionFolder: folder),
          )
    except CatchableError as error:
      catalog.catalogLoading = false
      catalog.status = "Could not parse the VS Code language catalog: " & error.msg
      emit catalog.vscodeGrammarCatalogDidUpdate()
  of vgakManifest:
    try:
      let candidates = parseVscodeGrammarManifest(
        request.extensionFolder, catalog.tree.sha, readFile(path), catalog.tree
      )
      catalog.allCandidates.add candidates
    except CatchableError:
      inc catalog.failedManifests
    inc catalog.manifestsLoaded
    if catalog.manifestsLoaded >= catalog.manifestsTotal:
      catalog.finishCatalogSearch()
    else:
      catalog.status =
        "Loading VS Code language metadata (" & $catalog.manifestsLoaded & " of " &
        $catalog.manifestsTotal & ")."
      emit catalog.vscodeGrammarCatalogDidUpdate()
  of vgakGrammar:
    if catalog.installing.isNone:
      return
    try:
      let content = readFile(path)
      if content.len > KosmoVscodeGrammarMaximumBytes:
        raise newException(ValueError, "grammar exceeds the 4 MiB safety limit")
      catalog.installContents[request.path] = content
      dec catalog.installRemaining
      if catalog.installRemaining == 0:
        catalog.finishGrammarInstall()
      else:
        catalog.status =
          "Downloading " & catalog.installing.get().name & " grammars (" &
          $catalog.installContents.len & " of " &
          $catalog.installing.get().grammarFiles.len & ")."
        emit catalog.vscodeGrammarCatalogDidUpdate()
    except CatchableError as error:
      catalog.processAsset(request, url, "", error.msg)

proc receiveUrlAsset(
    catalog: KosmoVscodeGrammarCatalog, handle: nimkit.UrlAssetHandle
) {.slot.} =
  if catalog.closed or handle.isNil:
    return
  let identifier = handle.identifier()
  if identifier notin catalog.pending:
    return
  let request = catalog.pending[identifier]
  catalog.pending.del(identifier)
  if handle.succeeded():
    catalog.processAsset(request, handle.result().url, handle.result().path)
  else:
    catalog.processAsset(request, handle.result().url, "", handle.result().errorMessage)

proc newKosmoVscodeGrammarCatalog*(): KosmoVscodeGrammarCatalog =
  ## Create a lazy catalog controller; its network worker starts on first search.
  KosmoVscodeGrammarCatalog(
    pending: initTable[uint64, VscodeGrammarAssetRequest](),
    installContents: initTable[string, string](),
  )

proc ensureLoader(catalog: KosmoVscodeGrammarCatalog) =
  if not catalog.loader.isNil or catalog.closed:
    return
  catalog.loader = nimkit.newUrlAssetLoader(
    "kosmo-vscode-grammars", maximumAssetBytes = VscodeCatalogMaximumBytes
  )
  catalog.loader.connect(
    nimkit.urlAssetDidFinish, catalog, KosmoVscodeGrammarCatalog.receiveUrlAsset
  )

proc search*(catalog: KosmoVscodeGrammarCatalog, query: string) =
  ## Search the built-in VS Code repository's language grammars.
  if catalog.isNil or catalog.closed:
    return
  catalog.query = query.strip()
  catalog.candidates.setLen(0)
  if catalog.query.normalizedSearchText().len < 2:
    catalog.status =
      "Enter at least two characters to search built-in VS Code languages."
    emit catalog.vscodeGrammarCatalogDidUpdate()
    return
  if catalog.catalogReady:
    catalog.finishCatalogSearch()
    return
  if catalog.catalogLoading:
    catalog.status = "Loading the VS Code language catalog."
    emit catalog.vscodeGrammarCatalogDidUpdate()
    return
  catalog.ensureLoader()
  catalog.catalogLoading = true
  catalog.status = "Loading the VS Code language catalog."
  emit catalog.vscodeGrammarCatalogDidUpdate()
  try:
    discard catalog.loader.removeCachedAsset(VscodeRepositoryTreeUrl)
    catalog.requestAsset(
      VscodeRepositoryTreeUrl, VscodeGrammarAssetRequest(kind: vgakTree)
    )
  except CatchableError as error:
    catalog.catalogLoading = false
    catalog.status = "Could not request the VS Code language catalog: " & error.msg
    emit catalog.vscodeGrammarCatalogDidUpdate()

proc candidates*(catalog: KosmoVscodeGrammarCatalog): seq[VscodeGrammarCandidate] =
  if not catalog.isNil:
    result = catalog.candidates

func status*(catalog: KosmoVscodeGrammarCatalog): string =
  if not catalog.isNil:
    result = catalog.status

func isBusy*(catalog: KosmoVscodeGrammarCatalog): bool =
  not catalog.isNil and (catalog.catalogLoading or catalog.installing.isSome)

proc install*(catalog: KosmoVscodeGrammarCatalog, candidateId: string) =
  ## Download, parse, and install the selected language's grammar sources.
  if catalog.isNil or catalog.closed or catalog.installing.isSome:
    return
  for candidate in catalog.candidates:
    if candidate.id != candidateId:
      continue
    catalog.installing = some(candidate)
    catalog.installContents.clear()
    catalog.installRemaining = candidate.grammarFiles.len
    catalog.status =
      "Downloading " & candidate.name & " grammars (0 of " & $candidate.grammarFiles.len &
      ")."
    emit catalog.vscodeGrammarCatalogDidUpdate()
    try:
      for file in candidate.grammarFiles:
        catalog.requestAsset(
          grammarUrl(candidate.sourceCommit, candidate.extensionFolder, file.path),
          VscodeGrammarAssetRequest(kind: vgakGrammar, path: file.path),
        )
    except CatchableError as error:
      catalog.status = "Could not download " & candidate.name & ": " & error.msg
      catalog.installing = none(VscodeGrammarCandidate)
      catalog.installContents.clear()
      catalog.installRemaining = 0
      emit catalog.vscodeGrammarCatalogDidUpdate()
    return

proc close*(catalog: KosmoVscodeGrammarCatalog) =
  if catalog.isNil or catalog.closed:
    return
  catalog.closed = true
  if not catalog.loader.isNil:
    catalog.loader.close()
    catalog.loader = nil
  catalog.pending.clear()
  catalog.installContents.clear()
  catalog.installing = none(VscodeGrammarCandidate)
