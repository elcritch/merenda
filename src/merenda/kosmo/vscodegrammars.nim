## Discovery through Open VSX and installation of VS Code TextMate grammar packages.

import std/[algorithm, json, options, os, sets, strutils, tables, tempfiles, times, uri]

import crunchy/[common, sha256]
import matter/rawgrammar
import zippy/ziparchives
import sigils/core
import ../nimkit as nimkit
import ../nimkit/foundation/textsearch

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
    sourceVersion*: string
    archiveUrl*: string
    extensions*: seq[string]
    fileNames*: seq[string]
    grammarFiles*: seq[VscodeGrammarFile]

  InstalledVscodeGrammar* = object
    candidate*: VscodeGrammarCandidate
    directory*: string
    sources*: seq[tuple[path, content, scopeName, languageId: string]]

  OpenVsxGrammarExtension* = object
    publisher*, name*, version*: string
    archiveUrl*, manifestUrl*: string

  VscodeGrammarAssetKind = enum
    vgakSearch
    vgakManifest
    vgakArchive

  VscodeGrammarAssetRequest = object
    kind: VscodeGrammarAssetKind
    generation: int
    extension: OpenVsxGrammarExtension

  KosmoVscodeGrammarCatalog* = ref object of Agent
    loader: nimkit.UrlAssetLoader
    pending: Table[uint64, VscodeGrammarAssetRequest]
    candidates: seq[VscodeGrammarCandidate]
    generation: int
    status: string
    catalogLoading: bool
    manifestsLoaded, manifestsTotal, failedManifests: int
    installing: Option[VscodeGrammarCandidate]
    closed: bool

  VscodeGrammarTree* = object
    sha*: string
    paths: HashSet[string]
    extensionFolders*: seq[string]

func defaultKosmoVscodeGrammarDirectory*(): string =
  ## Return Kosmo's user configuration folder for installed grammars.
  getConfigDir() / "kosmo" / KosmoVscodeGrammarDirectoryName

proc viewerGrammarSources*(
    installed: openArray[InstalledVscodeGrammar]
): seq[nimkit.MatterGrammarSource] =
  ## Convert validated installations to value snapshots for viewer workers.
  for grammar in installed:
    for source in grammar.sources:
      var converted = nimkit.MatterGrammarSource(
        path: source.path, content: source.content, scopeName: source.scopeName
      )
      if source.path == grammar.directory / grammar.candidate.rootPath:
        converted.languageId = grammar.candidate.languageId
        converted.extensions = grammar.candidate.extensions
        converted.fileNames = grammar.candidate.fileNames
      result.add move converted

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

proc parseGrammarManifest(
    extensionFolder, content: string, paths: HashSet[string], prefix: string
): seq[VscodeGrammarCandidate] =
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
    let fullPath = prefix & path
    if fullPath notin paths or path in seenPaths:
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
      extensions: language.extensions,
      fileNames: language.fileNames,
      grammarFiles: grammarFiles,
    )

proc parseVscodeGrammarManifest*(
    extensionFolder, sourceCommit, content: string, tree: VscodeGrammarTree
): seq[VscodeGrammarCandidate] =
  ## Parse a grammar manifest from a pinned VS Code repository tree.
  if not extensionFolder.validExtensionFolder() or not sourceCommit.validCommitSha():
    raise newException(ValueError, "invalid VS Code extension identity")
  result = parseGrammarManifest(
    extensionFolder, content, tree.paths, "extensions/" & extensionFolder & "/"
  )
  for candidate in result.mitems:
    candidate.sourceCommit = sourceCommit

proc validRegistryVersion(value: string): bool =
  value.validExtensionFolder() and value notin ["latest", "pre-release"]

proc validArchiveUrl(value, version: string): bool =
  let url = parseUri(value)
  url.scheme == "https" and url.hostname == "open-vsx.org" and url.username.len == 0 and
    url.password.len == 0 and url.port.len == 0 and url.query.len == 0 and
    url.anchor.len == 0 and url.path.startsWith("/api/") and
    ("/" & version & "/file/") in url.path and url.path.endsWith(".vsix") and
    "/../" notin url.path

proc validGrammarSource(candidate: VscodeGrammarCandidate): bool =
  if candidate.archiveUrl.len > 0:
    candidate.sourceVersion.validRegistryVersion() and
      candidate.archiveUrl.validArchiveUrl(candidate.sourceVersion)
  else:
    candidate.sourceCommit.validCommitSha()

proc parseOpenVsxGrammarSearch*(content: string): seq[OpenVsxGrammarExtension] =
  ## Read pinned extension identities from an Open VSX search response.
  let response = parseJson(content)
  if response.kind != JObject or not response.hasKey("extensions") or
      response["extensions"].kind != JArray:
    raise newException(ValueError, "Open VSX returned no extension list")
  var seen = initHashSet[string]()
  for entry in response["extensions"]:
    let publisher = entry.jsonString("namespace")
    let name = entry.jsonString("name")
    let version = entry.jsonString("version")
    if publisher.validExtensionFolder() and name.validExtensionFolder() and
        version.validRegistryVersion() and entry.hasKey("files"):
      let archiveUrl = entry["files"].jsonString("download")
      if archiveUrl.validArchiveUrl(version) and archiveUrl notin seen:
        seen.incl archiveUrl
        result.add OpenVsxGrammarExtension(
          publisher: publisher,
          name: name,
          version: version,
          archiveUrl: archiveUrl,
          manifestUrl: archiveUrl[0 .. archiveUrl.rfind('/')] & "package.json",
        )

proc parseOpenVsxGrammarManifest*(
    extension: OpenVsxGrammarExtension, content: string
): seq[VscodeGrammarCandidate] =
  ## Return only language grammars contributed by this registry extension.
  let package = parseJson(content)
  if package.jsonString("publisher") != extension.publisher or
      package.jsonString("name") != extension.name or
      package.jsonString("version") != extension.version or
      not extension.publisher.validExtensionFolder() or
      not extension.name.validExtensionFolder() or
      not extension.version.validRegistryVersion() or
      not extension.archiveUrl.validArchiveUrl(extension.version):
    raise newException(ValueError, "Open VSX manifest does not match its extension")
  var paths = initHashSet[string]()
  if package.hasKey("contributes") and package["contributes"].kind == JObject:
    let contributions = package["contributes"]
    if contributions.hasKey("grammars") and contributions["grammars"].kind == JArray:
      for grammar in contributions["grammars"]:
        paths.incl grammar.jsonString("path").safeRelativeGrammarPath()
  result =
    parseGrammarManifest(extension.publisher & "." & extension.name, content, paths, "")
  for candidate in result.mitems:
    candidate.id = "openvsx:" & candidate.id
    candidate.sourceVersion = extension.version
    candidate.archiveUrl = extension.archiveUrl

proc normalizedSearchText(value: string): string =
  for character in value.toLowerAscii():
    if character.isAlphaNumeric and ord(character) < 128:
      result.add character

proc matchesVscodeGrammarQuery(
    candidate: VscodeGrammarCandidate,
    pattern: TextSearchPattern,
    compactPattern: Option[TextSearchPattern],
): bool =
  var fields = @[
    candidate.name, candidate.extensionFolder, candidate.languageId, candidate.scopeName
  ]
  fields.add candidate.extensions
  fields.add candidate.fileNames
  for field in fields:
    if pattern.contains(field) or (
      compactPattern.isSome and compactPattern.get.contains(
        field.normalizedSearchText()
      )
    ):
      return true

proc matchesVscodeGrammarQuery*(
    candidate: VscodeGrammarCandidate, query: string, regularExpression = false
): bool =
  ## Match metadata with Reni; literal queries also ignore punctuation as before.
  let source =
    if regularExpression:
      query
    else:
      query.strip()
  if source.len == 0:
    return
  let compactQuery = source.normalizedSearchText()
  if not regularExpression and compactQuery.len == 0:
    return
  let compactPattern =
    if regularExpression:
      none(TextSearchPattern)
    else:
      some(initTextSearchPattern(compactQuery, caseSensitive = false))
  candidate.matchesVscodeGrammarQuery(
    initTextSearchPattern(source, regularExpression, caseSensitive = false),
    compactPattern,
  )

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
  result["sourceVersion"] = %candidate.sourceVersion
  result["archiveUrl"] = %candidate.archiveUrl
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
  result.sourceVersion = node.jsonString("sourceVersion")
  result.archiveUrl = node.jsonString("archiveUrl")
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
      not result.validGrammarSource() or
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

proc readOpenVsxGrammarArchive*(
    candidate: VscodeGrammarCandidate, archivePath: string
): Table[string, string] =
  ## Read declared grammar members only; extension code is never extracted.
  if not candidate.validGrammarSource() or candidate.archiveUrl.len == 0:
    raise newException(ValueError, "invalid Open VSX grammar package")
  if candidate.grammarFiles.len == 0 or candidate.grammarFiles.len > 32:
    raise newException(ValueError, "invalid number of grammar files")
  let archive = openZipArchive(archivePath)
  defer:
    archive.close()
  var totalBytes: int
  for file in candidate.grammarFiles:
    let path = file.path.safeRelativeGrammarPath()
    let content = archive.extractFile("extension/" & path)
    totalBytes += content.len
    if content.len > KosmoVscodeGrammarMaximumBytes or totalBytes > 16 * 1024 * 1024:
      raise newException(ValueError, "extension grammars exceed the size limit")
    result[path] = content
  candidate.validateVscodeGrammarFiles(result)

proc installVscodeGrammar*(
    candidate: VscodeGrammarCandidate,
    contents: Table[string, string],
    grammarDirectory = defaultKosmoVscodeGrammarDirectory(),
): string =
  ## Validate and atomically install one VS Code language package under Kosmo config.
  candidate.validateVscodeGrammarFiles(contents)
  if not candidate.extensionFolder.validExtensionFolder() or
      not candidate.validGrammarSource():
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
  OpenVsxSearchUrl = "https://open-vsx.org/api/-/search"
  OpenVsxSearchPageSize = 40
  OpenVsxMaximumPackageBytes = 128 * 1024 * 1024

proc vscodeGrammarCatalogDidUpdate*(catalog: KosmoVscodeGrammarCatalog) {.signal.}
proc vscodeGrammarDidInstall*(
  catalog: KosmoVscodeGrammarCatalog, directory: string
) {.signal.}

proc processAsset(
  catalog: KosmoVscodeGrammarCatalog,
  request: VscodeGrammarAssetRequest,
  path: string,
  errorMessage = "",
)

proc requestAsset(
    catalog: KosmoVscodeGrammarCatalog, url: string, request: VscodeGrammarAssetRequest
) =
  if catalog.closed or catalog.loader.isNil:
    return
  let handle = catalog.loader.load(url)
  if handle.isFinished():
    catalog.processAsset(request, handle.result().path, handle.result().errorMessage)
  else:
    catalog.pending[handle.identifier()] = request

proc finishCatalogSearch(catalog: KosmoVscodeGrammarCatalog) =
  catalog.catalogLoading = false
  catalog.candidates.sort do(left, right: VscodeGrammarCandidate) -> int:
    result = cmpIgnoreCase(left.name, right.name)
    if result == 0:
      result = cmp(left.id, right.id)
  catalog.status =
    if catalog.candidates.len == 0:
      "No TextMate grammars found. Try another language or extension name."
    else:
      $catalog.candidates.len & " grammars found on Open VSX."
  if catalog.manifestsTotal == OpenVsxSearchPageSize:
    catalog.status.add(" Showing the first 40 extensions; refine your search for more.")
  if catalog.failedManifests > 0:
    catalog.status.add(
      " " & $catalog.failedManifests & " extension manifests could not be read."
    )
  emit catalog.vscodeGrammarCatalogDidUpdate()

proc processAsset(
    catalog: KosmoVscodeGrammarCatalog,
    request: VscodeGrammarAssetRequest,
    path: string,
    errorMessage: string,
) =
  if catalog.closed or
      (request.kind != vgakArchive and request.generation != catalog.generation):
    return
  var failure = errorMessage
  if failure.len == 0 and path.len == 0:
    failure = "The download did not return a file."
  try:
    if failure.len > 0:
      raise newException(IOError, failure)
    case request.kind
    of vgakSearch:
      let extensions = parseOpenVsxGrammarSearch(readFile(path))
      catalog.manifestsTotal = extensions.len
      catalog.manifestsLoaded = 0
      catalog.failedManifests = 0
      if extensions.len == 0:
        catalog.finishCatalogSearch()
      else:
        catalog.status = "Checking Open VSX extensions for TextMate grammars."
        emit catalog.vscodeGrammarCatalogDidUpdate()
        for extension in extensions:
          catalog.requestAsset(
            extension.manifestUrl,
            VscodeGrammarAssetRequest(
              kind: vgakManifest, generation: request.generation, extension: extension
            ),
          )
    of vgakManifest:
      catalog.candidates.add parseOpenVsxGrammarManifest(
        request.extension, readFile(path)
      )
    of vgakArchive:
      if catalog.installing.isSome:
        let candidate = catalog.installing.get()
        let contents = candidate.readOpenVsxGrammarArchive(path)
        let directory = installVscodeGrammar(candidate, contents)
        catalog.installing = none(VscodeGrammarCandidate)
        catalog.status =
          "Installed " & candidate.name & " (" & candidate.scopeName & ")."
        emit catalog.vscodeGrammarDidInstall(directory)
        emit catalog.vscodeGrammarCatalogDidUpdate()
  except CatchableError as error:
    case request.kind
    of vgakSearch:
      catalog.catalogLoading = false
      catalog.status = "Could not search Open VSX: " & error.msg
      emit catalog.vscodeGrammarCatalogDidUpdate()
    of vgakManifest:
      inc catalog.failedManifests
    of vgakArchive:
      catalog.installing = none(VscodeGrammarCandidate)
      catalog.status = "Could not install the grammar: " & error.msg
      emit catalog.vscodeGrammarCatalogDidUpdate()
  if request.kind == vgakManifest:
    inc catalog.manifestsLoaded
    if catalog.manifestsLoaded >= catalog.manifestsTotal:
      catalog.finishCatalogSearch()

proc receiveUrlAsset(
    catalog: KosmoVscodeGrammarCatalog, handle: nimkit.UrlAssetHandle
) {.slot.} =
  if catalog.closed or handle.isNil or handle.identifier() notin catalog.pending:
    return
  let request = catalog.pending[handle.identifier()]
  catalog.pending.del(handle.identifier())
  catalog.processAsset(request, handle.result().path, handle.result().errorMessage)

proc newKosmoVscodeGrammarCatalog*(): KosmoVscodeGrammarCatalog =
  ## Create a lazy Open VSX grammar search controller.
  KosmoVscodeGrammarCatalog(pending: initTable[uint64, VscodeGrammarAssetRequest]())

proc initLoader(catalog: KosmoVscodeGrammarCatalog) =
  if catalog.loader.isNil and not catalog.closed:
    catalog.loader = nimkit.newUrlAssetLoader(
      "kosmo-openvsx-grammars", maximumAssetBytes = OpenVsxMaximumPackageBytes
    )
    catalog.loader.connect(
      nimkit.urlAssetDidFinish, catalog, KosmoVscodeGrammarCatalog.receiveUrlAsset
    )

proc search*(catalog: KosmoVscodeGrammarCatalog, query: string) =
  ## Search Open VSX using plain language or extension names.
  if catalog.isNil or catalog.closed or catalog.installing.isSome:
    return
  inc catalog.generation
  catalog.catalogLoading = false
  catalog.candidates.setLen(0)
  let query = query.strip()
  if query.len < 2:
    catalog.status = "Enter at least two characters to search Open VSX."
    emit catalog.vscodeGrammarCatalogDidUpdate()
    return
  catalog.initLoader()
  catalog.catalogLoading = true
  catalog.status = "Searching Open VSX for language grammars."
  emit catalog.vscodeGrammarCatalogDidUpdate()
  let url =
    OpenVsxSearchUrl & "?query=" & encodeUrl(query) &
    "&category=Programming%20Languages&size=" & $OpenVsxSearchPageSize
  try:
    let cached = catalog.loader.cachedAssetPath(url)
    if fileExists(cached) and
        getTime() - getLastModificationTime(cached) > initDuration(hours = 24):
      discard catalog.loader.removeCachedAsset(url)
    catalog.requestAsset(
      url, VscodeGrammarAssetRequest(kind: vgakSearch, generation: catalog.generation)
    )
  except CatchableError as error:
    catalog.catalogLoading = false
    catalog.status = "Could not search Open VSX: " & error.msg
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
  ## Download a pinned extension and install only its declared TextMate grammars.
  if catalog.isNil or catalog.closed or catalog.isBusy():
    return
  for candidate in catalog.candidates:
    if candidate.id == candidateId:
      catalog.installing = some(candidate)
      catalog.status = "Downloading " & candidate.name & " from Open VSX."
      emit catalog.vscodeGrammarCatalogDidUpdate()
      try:
        catalog.requestAsset(
          candidate.archiveUrl, VscodeGrammarAssetRequest(kind: vgakArchive)
        )
      except CatchableError as error:
        catalog.installing = none(VscodeGrammarCandidate)
        catalog.status = "Could not download the grammar: " & error.msg
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
  catalog.installing = none(VscodeGrammarCandidate)
