## Dispatch before integration suites so file-size limits affect only this child.

when defined(posix):
  import std/[os, posix, strutils]

  import merenda/kosmo/config
  import merenda/nimkit/app/documents
  import merenda/nimkit/foundation/atomicfiles
  import merenda/nimkit/resources/resrccore
  import merenda/tekton/editor

  const AtomicSaveFailureProbe* = "--merenda-atomic-save-failure"

  var fileSizeLimit {.importc: "RLIMIT_FSIZE", header: "<sys/resource.h>".}: cint

  proc probeFailedSave(kind, path: string) =
    var limit: RLimit
    doAssert getrlimit(fileSizeLimit, limit) == 0
    limit.rlim_cur = 64
    doAssert setrlimit(fileSizeLimit, limit) == 0
    discard signal(SIGXFSZ, SIG_IGN)

    case kind
    of "buffered", "large":
      let payload = "x".repeat(if kind == "buffered": 128 else: 65_536)
      var failed = false
      try:
        atomicWriteFile(path, payload)
      except IOError, OSError:
        failed = true
      doAssert failed, "the file-size limit must reject the save"
    of "config":
      let config = KosmoConfig(merendaFont: "replacement")
      doAssert not config.saveKosmoConfig(path)
    of "tekton":
      let originalUrl = path & ".original.cbor"
      let document = newResourceEditorDocument(
        namespace = "draft".repeat(16_384), fileUrl = originalUrl
      )
      document.documentEdited = true
      doAssert not document.saveAs(path)
      doAssert document.isDocumentEdited()
      doAssert document.fileUrl() == originalUrl
      doAssert document.ioDiagnostics().hasErrors()
      doAssert document.ioDiagnostics().entries[0].code == "resource.file.unavailable"
    else:
      doAssert false, "unknown atomic save probe: " & kind

  if paramCount() == 3 and paramStr(1) == AtomicSaveFailureProbe:
    probeFailedSave(paramStr(2), paramStr(3))
    quit(0)
