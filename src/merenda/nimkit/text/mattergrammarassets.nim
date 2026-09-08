## Compile-time embedded Matter grammar archives shared by NimKit and Kosmo.
##
## Applications can use the bundled grammars without locating Matter's package
## data at runtime. Archive validation and extraction live here so each consumer
## embeds the same source constants instead of maintaining its own archive list.

import std/[compilesettings, os]

import matter/[engine, grammarpackages]
import zippy
import zippy/crc

const ZipLocalHeader = "PK\x03\x04"

proc findMatterPackageRoot(): string {.compileTime.} =
  for searchPath in querySettingSeq(MultipleValueSetting.searchPaths):
    let
      sourceDir = searchPath
      packageRoot = sourceDir.parentDir
    if fileExists(sourceDir / "matter.nim") and
        dirExists(packageRoot / "data" / "grammars"):
      return packageRoot
  raise newException(ValueError, "could not locate Matter's grammar archives")

const MatterPackageRoot = findMatterPackageRoot()

template embedGrammarArchive(package: untyped): untyped =
  (
    path: package.dataArchivePath,
    contents: staticRead(MatterPackageRoot / package.dataArchivePath),
  )

const EmbeddedGrammarArchives = block:
  var archives: array[knownPackages.len, tuple[path, contents: string]]
  for index, package in knownPackages:
    archives[index] = embedGrammarArchive(package)
  archives

func littleEndian16(contents: string, offset: int): int =
  ord(contents[offset]) or (ord(contents[offset + 1]) shl 8)

func littleEndian32(contents: string, offset: int): uint32 =
  uint32(ord(contents[offset])) or (uint32(ord(contents[offset + 1])) shl 8) or
    (uint32(ord(contents[offset + 2])) shl 16) or
    (uint32(ord(contents[offset + 3])) shl 24)

func archiveContents(path: string): string =
  for archive in EmbeddedGrammarArchives:
    if archive.path == path:
      return archive.contents

proc readZipMember(contents, member: string): string =
  var offset = 0
  while offset + 30 <= contents.len and
      contents[offset ..< offset + ZipLocalHeader.len] == ZipLocalHeader:
    let
      flags = contents.littleEndian16(offset + 6)
      compression = contents.littleEndian16(offset + 8)
      expectedCrc32 = contents.littleEndian32(offset + 14)
      compressedSize = contents.littleEndian32(offset + 18).int
      uncompressedSize = contents.littleEndian32(offset + 22).int
      nameSize = contents.littleEndian16(offset + 26)
      extraSize = contents.littleEndian16(offset + 28)
      nameStart = offset + 30
      dataStart = nameStart + nameSize + extraSize
      dataStop = dataStart + compressedSize
    if flags != 0 or compression notin [0, 8] or dataStart > contents.len or
        dataStop > contents.len:
      raise newException(MatterError, "invalid bundled Matter grammar archive")
    if contents[nameStart ..< nameStart + nameSize] == member:
      let compressed = contents[dataStart ..< dataStop]
      try:
        case compression
        of 0:
          result = compressed
        of 8:
          result = zippy.uncompress(compressed, zippy.dfDeflate)
        else:
          discard
      except zippy.ZippyError as error:
        raise newException(
          MatterError, "invalid bundled Matter grammar archive: " & error.msg
        )
      if result.len != uncompressedSize or crc32(result) != expectedCrc32:
        raise newException(MatterError, "invalid bundled Matter grammar archive")
      return
    offset = dataStop
  raise newException(MatterError, "missing bundled Matter grammar: " & member)

proc bundledMatterGrammarContents*(contribution: GrammarContribution): string =
  ## Return one validated grammar source from Matter's embedded archive catalog.
  let archive = archiveContents(contribution.dataArchivePath)
  if archive.len == 0:
    raise newException(
      MatterError, "missing bundled Matter archive: " & contribution.dataArchivePath
    )
  archive.readZipMember(contribution.archiveMember)
