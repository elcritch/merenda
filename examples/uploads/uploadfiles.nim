## File values, validation and the simulated backend shared by the upload examples.
import std/[os, sequtils, strutils]
import sigils/[core, threadProxies, threads]
import merenda/foundation/backgroundworkers

type
  FileField* = enum
    ffName
    ffAltText
    ffCategory
    ffSubcategory

  UploadFile* = object
    id*: int
    path*: string
    name*, altText*: string
    category*, subcategory*: string
    tags*: seq[string]
    special*: bool

  TagBackend* = ref object of AgentActor

const
  Categories* = [
    (name: "Photos", subcategories: @["Landscape", "Portrait", "Product"]),
    (name: "Documents", subcategories: @["Invoice", "Contract", "Report"]),
    (name: "Media", subcategories: @["Audio", "Video", "Slides"]),
  ]
  TagCatalog = [
    "brand", "campaign", "contract", "draft", "final", "internal", "interview",
    "invoice", "landscape", "launch", "legal", "nature", "night", "nim", "portrait",
    "press", "product", "public", "quarterly", "release", "review", "summer", "sunset",
    "team", "travel",
  ]
  SearchLatencyMs = 150
  SamplePaths* = [
    "~/Pictures/sunset-over-lake.jpg", "~/Documents/contract-2026.pdf",
    "~/Pictures/team-offsite.png", "~/Music/podcast-intro.mp3",
    "~/Documents/q3-report.pdf",
  ]
  ImageExtensions = [".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"]

proc subcategoriesFor*(category: string): seq[string] =
  for entry in Categories:
    if entry.name == category:
      return entry.subcategories

proc isImage*(file: UploadFile): bool =
  file.path.splitFile.ext.toLowerAscii in ImageExtensions

proc issueFor*(file: UploadFile, field: FileField): string =
  case field
  of ffName:
    if file.name.strip.len == 0:
      result = "A file name is required."
  of ffAltText:
    if file.isImage and file.altText.strip.len == 0:
      result = "Images need alt text."
  of ffCategory:
    if file.category.len == 0:
      result = "Choose a category."
  of ffSubcategory:
    if file.category.len > 0 and file.subcategory.len == 0:
      result = "Choose a subcategory."

proc isValid*(file: UploadFile): bool =
  allIt(FileField, file.issueFor(it).len == 0)

proc displayName*(file: UploadFile): string =
  if file.name.strip.len > 0: file.name else: "Untitled file"

proc detailLine*(file: UploadFile): string =
  ## A one-line summary under the file name in the list.
  var parts = @[file.path.splitFile.ext.strip(chars = {'.'}).toUpperAscii]
  if file.category.len > 0:
    parts.add file.category &
      (if file.subcategory.len > 0: " › " & file.subcategory
      else: "")
  if file.special:
    parts.add "Special"
  if not file.isValid:
    parts.add "Needs details"
  parts.join("  ·  ")

proc uploadSummary*(files: openArray[UploadFile]): string =
  var lines: seq[string]
  for file in files:
    var line = file.name & " -> " & file.category & "/" & file.subcategory
    if file.tags.len > 0:
      line.add " #" & file.tags.join(" #")
    if file.special:
      line.add " (special)"
    lines.add line
  "Uploaded " & lines.join("; ")

proc searchTags*(backend: AgentProxy[TagBackend], query: string) {.signal.}
proc tagsFound*(backend: TagBackend, query: string, tags: seq[string]) {.signal.}

proc searchTags*(backend: TagBackend, query: string) {.slot.} =
  ## Runs on a worker thread and simulates a backend round trip.
  sleep(SearchLatencyMs)
  let found = TagCatalog.filterIt(it.startsWith(query))
  emit backend.tagsFound(query, found)

proc newTagBackend*(): AgentProxy[TagBackend] =
  var backend = TagBackend()
  result = backend.moveToThread(backgroundWorkerPool())
  connectThreaded(result, searchTags, result, searchTags)
