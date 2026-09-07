## Installation of statically embedded ZIP resources into an application cache.

import std/[appdirs, os, paths, strutils, tempfiles]

import crunchy/[common, sha256]
import zippy/ziparchives

const
  NimKitAssetCacheDirectoryName* = "assets"
  DefaultMaximumEmbeddedAssetBytes* = 64'i64 * 1024'i64 * 1024'i64

type
  EmbeddedZipAsset* = object ## One file stored in an embedded ZIP archive.
    fileName*: string
    archiveMember*: string
    archiveContents*: string
    contentSha256*: string
    maximumContentBytes*: int64

  EmbeddedAssetInstallState* = enum
    eaisFailed
    eaisReady

  EmbeddedAssetInstallResult* = object
    ## Result of installing one embedded asset into the cache.
    state*: EmbeddedAssetInstallState
    path*: string
    byteLength*: int64
    cacheHit*: bool
    errorMessage*: string

func validateFileName(fileName: string) =
  if fileName.len == 0:
    raise newException(ValueError, "embedded asset file name cannot be empty")
  if fileName in [".", ".."] or '/' in fileName or '\\' in fileName or '\0' in fileName:
    raise newException(ValueError, "embedded asset file name must be a base name")

func validateSha256(value: string) =
  if value.len != 64:
    raise newException(ValueError, "embedded asset SHA-256 must have 64 digits")
  for character in value:
    if character notin {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
      raise newException(ValueError, "embedded asset SHA-256 must be hexadecimal")

func initEmbeddedZipAsset*(
    fileName, archiveContents, contentSha256: string,
    archiveMember = "",
    maximumContentBytes = DefaultMaximumEmbeddedAssetBytes,
): EmbeddedZipAsset =
  ## Describe one trusted, statically embedded ZIP member and its expected contents.
  ##
  ## `maximumContentBytes` rejects an oversized member after Zippy extracts it.
  ## Callers must still treat the compiled archive itself as trusted because Zippy's
  ## reader does not expose a pre-extraction uncompressed-size query.
  fileName.validateFileName()
  contentSha256.validateSha256()
  if archiveContents.len == 0:
    raise newException(ValueError, "embedded ZIP archive cannot be empty")
  if maximumContentBytes <= 0:
    raise newException(ValueError, "embedded asset size limit must be positive")
  result = EmbeddedZipAsset(
    fileName: fileName,
    archiveMember: if archiveMember.len > 0: archiveMember else: fileName,
    archiveContents: archiveContents,
    contentSha256: contentSha256.toLowerAscii(),
    maximumContentBytes: maximumContentBytes,
  )

func succeeded*(installResult: EmbeddedAssetInstallResult): bool =
  ## Return whether the asset is ready for use at `installResult.path`.
  installResult.state == eaisReady

proc nimkitAssetCacheDirectory*(applicationIdentifier: string): string =
  ## Return the platform cache directory for one application's installed assets.
  if applicationIdentifier.strip().len == 0:
    raise newException(ValueError, "application identifier cannot be empty")
  $(
    appdirs.getCacheDir(Path(applicationIdentifier)) /
    Path(NimKitAssetCacheDirectoryName)
  )

func embeddedAssetCachePath(asset: EmbeddedZipAsset, cacheDirectory: string): string =
  cacheDirectory / (asset.contentSha256.toLowerAscii() & "-" & asset.fileName)

proc cachedAssetIsValid(
    path, expectedSha256: string, maximumContentBytes: int64
): bool =
  if not fileExists(path):
    return
  try:
    if getFileSize(path) > maximumContentBytes:
      return
    result = sha256(readFile(path)).toHex().toLowerAscii() == expectedSha256
  except OSError:
    discard

proc removeFileIfPresent(path: string) =
  if path.len > 0 and fileExists(path):
    try:
      removeFile(path)
    except OSError:
      discard

proc installZipAsset(
    asset: EmbeddedZipAsset,
    applicationIdentifier: string,
    cacheDirectory = "",
    extractedContents = "",
    hasExtractedContents = false,
): EmbeddedAssetInstallResult =
  ## Extract and verify an embedded ZIP member in the application asset cache.
  ##
  ## The returned path is content-addressed by the expected SHA-256. Installation
  ## failures are reported in the result so applications can choose a fallback.
  var
    archivePath: string
    outputPath: string
    reader: ZipArchiveReader
  try:
    asset.fileName.validateFileName()
    asset.contentSha256.validateSha256()
    if not hasExtractedContents and asset.archiveContents.len == 0:
      raise newException(ValueError, "embedded ZIP archive cannot be empty")
    if asset.archiveMember.len == 0:
      raise newException(ValueError, "embedded ZIP member cannot be empty")
    if asset.maximumContentBytes <= 0:
      raise newException(ValueError, "embedded asset size limit must be positive")

    let
      expectedSha256 = asset.contentSha256.toLowerAscii()
      resolvedCacheDirectory =
        if cacheDirectory.len > 0:
          cacheDirectory
        else:
          nimkitAssetCacheDirectory(applicationIdentifier)
      targetPath = asset.embeddedAssetCachePath(resolvedCacheDirectory)
    createDir(resolvedCacheDirectory)

    if targetPath.cachedAssetIsValid(expectedSha256, asset.maximumContentBytes):
      return EmbeddedAssetInstallResult(
        state: eaisReady,
        path: targetPath,
        byteLength: getFileSize(targetPath),
        cacheHit: true,
      )

    var contents = extractedContents
    if not hasExtractedContents:
      let archiveFile =
        createTempFile(".nimkit-embedded-", ".zip", resolvedCacheDirectory)
      archivePath = archiveFile.path
      archiveFile.cfile.close()
      writeFile(archivePath, asset.archiveContents)
      reader = openZipArchive(archivePath)
      contents = reader.extractFile(asset.archiveMember)
      reader.close()
      reader = nil
    if contents.len.int64 > asset.maximumContentBytes:
      raise newException(ValueError, "embedded asset exceeds its size limit")
    if sha256(contents).toHex().toLowerAscii() != expectedSha256:
      raise newException(ValueError, "embedded asset SHA-256 does not match")

    let outputFile =
      createTempFile(".nimkit-embedded-", ".part", resolvedCacheDirectory)
    outputPath = outputFile.path
    outputFile.cfile.close()
    writeFile(outputPath, contents)
    try:
      moveFile(outputPath, targetPath)
    except OSError:
      if targetPath.cachedAssetIsValid(expectedSha256, asset.maximumContentBytes):
        return EmbeddedAssetInstallResult(
          state: eaisReady,
          path: targetPath,
          byteLength: getFileSize(targetPath),
          cacheHit: true,
        )
      raise
    outputPath.setLen(0)

    result = EmbeddedAssetInstallResult(
      state: eaisReady, path: targetPath, byteLength: contents.len.int64
    )
  except CatchableError as error:
    result.errorMessage = error.msg
  finally:
    if not reader.isNil:
      try:
        reader.close()
      except OSError:
        discard
    archivePath.removeFileIfPresent()
    outputPath.removeFileIfPresent()

proc installEmbeddedZipAsset*(
    asset: EmbeddedZipAsset, applicationIdentifier: string, cacheDirectory = ""
): EmbeddedAssetInstallResult =
  ## Installs a trusted embedded member, verifying its expected SHA-256.
  installZipAsset(asset, applicationIdentifier, cacheDirectory)

proc installZipAssetFile*(
    archivePath, applicationIdentifier: string,
    cacheDirectory = "",
    archiveMember = "",
    maximumContentBytes = DefaultMaximumEmbeddedAssetBytes,
): EmbeddedAssetInstallResult =
  ## Installs a member of a trusted local ZIP into the embedded-asset cache.
  ## By default `Font.ttf.zip` selects the member `Font.ttf`.
  ## The extracted bytes determine the cache key; this does not authenticate the ZIP.
  ## As with embedded archives, the size check occurs after decompression.
  var reader: ZipArchiveReader
  try:
    if maximumContentBytes <= 0:
      raise newException(ValueError, "ZIP asset size limit must be positive")
    if getFileSize(archivePath) > maximumContentBytes:
      raise newException(ValueError, "ZIP asset archive exceeds its size limit")
    let member =
      if archiveMember.len > 0:
        archiveMember
      else:
        archivePath.extractFilename().changeFileExt("")
    reader = openZipArchive(archivePath)
    let contents = reader.extractFile(member)
    reader.close()
    reader = nil
    if contents.len.int64 > maximumContentBytes:
      raise newException(ValueError, "ZIP asset member exceeds its size limit")
    let asset = EmbeddedZipAsset(
      fileName: member.extractFilename(),
      archiveMember: member,
      contentSha256: sha256(contents).toHex().toLowerAscii(),
      maximumContentBytes: maximumContentBytes,
    )
    result = installZipAsset(
      asset,
      applicationIdentifier,
      cacheDirectory,
      contents,
      hasExtractedContents = true,
    )
  except CatchableError as error:
    result.errorMessage = error.msg
  finally:
    if not reader.isNil:
      try:
        reader.close()
      except OSError:
        discard
