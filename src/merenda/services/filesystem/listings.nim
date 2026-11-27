## Cached directory listings with entry limits.

import std/[algorithm, os, strutils, tables]

const DefaultFileBrowserEntryLimit* = 1_000

type
  FileBrowserEntryKind* = enum
    fbekFile
    fbekDirectory
    fbekSymbolicLink

  FileBrowserEntry* = object
    path*: string
    name*: string
    kind*: FileBrowserEntryKind

  FileBrowserDirectoryListing = object
    entries: seq[FileBrowserEntry]
    truncated: bool

  FileSystemBrowserModel* = object
    xListings: Table[string, seq[FileBrowserEntry]]
    xListingTruncation: Table[string, bool]
    xEntryLimit: int

func fileBrowserDisplayName*(path: string): string =
  result = path.extractFilename()
  if result.len == 0:
    result = path

proc isBrowsableDirectory*(path: string): bool =
  dirExists(path) and not symlinkExists(path)

func isDirectory*(entry: FileBrowserEntry): bool =
  entry.kind == fbekDirectory

func isFile*(entry: FileBrowserEntry): bool =
  entry.kind == fbekFile

func compareFileBrowserEntries(left, right: FileBrowserEntry): int =
  if left.isDirectory() != right.isDirectory():
    return if left.isDirectory(): -1 else: 1
  cmpIgnoreCase(left.name, right.name)

proc loadDirectoryEntries(
    directoryPath: string, maxEntries: int
): FileBrowserDirectoryListing =
  if not directoryPath.isBrowsableDirectory():
    return
  let entryLimit = max(maxEntries, 1)
  try:
    for component, path in walkDir(directoryPath, relative = false):
      if result.entries.len >= entryLimit:
        result.truncated = true
        break
      let kind =
        case component
        of pcFile: fbekFile
        of pcDir: fbekDirectory
        of pcLinkToFile, pcLinkToDir: fbekSymbolicLink
      result.entries.add FileBrowserEntry(
        path: path, name: path.fileBrowserDisplayName(), kind: kind
      )
    result.entries.sort(compareFileBrowserEntries)
  except OSError:
    discard

func initFileSystemBrowserModel*(
    entryLimit: Positive = DefaultFileBrowserEntryLimit
): FileSystemBrowserModel =
  FileSystemBrowserModel(
    xListings: initTable[string, seq[FileBrowserEntry]](),
    xListingTruncation: initTable[string, bool](),
    xEntryLimit: entryLimit.int,
  )

func entryLimit*(model: FileSystemBrowserModel): int =
  if model.xEntryLimit > 0: model.xEntryLimit else: DefaultFileBrowserEntryLimit

proc entries*(
    model: var FileSystemBrowserModel, directoryPath: string
): lent seq[FileBrowserEntry] =
  ## Return a cached listing, loading this directory on first access.
  if not model.xListings.hasKey(directoryPath):
    let listing = directoryPath.loadDirectoryEntries(model.entryLimit())
    model.xListings[directoryPath] = listing.entries
    model.xListingTruncation[directoryPath] = listing.truncated
  model.xListings[directoryPath]

proc isDirectoryLoaded*(model: FileSystemBrowserModel, directoryPath: string): bool =
  model.xListings.hasKey(directoryPath)

proc isDirectoryTruncated*(model: FileSystemBrowserModel, directoryPath: string): bool =
  if model.xListingTruncation.hasKey(directoryPath):
    result = model.xListingTruncation[directoryPath]

proc cachedDirectoryCount*(model: FileSystemBrowserModel): int =
  model.xListings.len

proc invalidate*(model: var FileSystemBrowserModel, directoryPath = "") =
  ## Drop one cached listing, or every listing when no path is supplied.
  if directoryPath.len == 0:
    model.xListings.clear()
    model.xListingTruncation.clear()
  else:
    model.xListings.del(directoryPath)
    model.xListingTruncation.del(directoryPath)

proc `entryLimit=`*(model: var FileSystemBrowserModel, value: Positive) =
  if model.xEntryLimit == value.int:
    return
  model.xEntryLimit = value.int
  model.invalidate()
