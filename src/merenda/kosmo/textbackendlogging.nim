## Report the text backend selected for the Kosmo process.
import pkg/chronicles
import figdraw

when runtimeTextBackends:
  import harfbuzzy as hb
  import harfbuzzy/raw as hbRaw

proc textBackendDiagnostic*(): tuple[backend, detail: string] =
  when runtimeTextBackends:
    try:
      hb.loadHarfbuzz()
    except hb.HarfBuzzLoadError as error:
      return ("pixie", "HarfBuzz could not be loaded: " & error.msg)
    if not hb.versionAtLeast(7, 0, 0):
      let version =
        if cast[pointer](hbRaw.hb_version_string) != nil:
          hb.versionString()
        else:
          "unknown"
      return (
        "pixie", "HarfBuzz " & version & " is too old; version 7.0 or newer is required"
      )
    try:
      hb.loadFribidi()
    except hb.FriBidiLoadError as error:
      return ("pixie", "FriBidi could not be loaded: " & error.msg)
    result.backend = textBackend()
    if result.backend == "pixie":
      result.detail = "HarfBuzz is missing required symbols"
    else:
      result.detail = "HarfBuzz and FriBidi loaded successfully"
  else:
    result = (textBackend(), "text backend selected at build time")

proc logTextBackend*() =
  let diagnostic = textBackendDiagnostic()
  if diagnostic.backend == "pixie" and runtimeTextBackends:
    warn "Using Pixie text backend", reason = diagnostic.detail
  else:
    info "Text backend selected",
      backend = diagnostic.backend, detail = diagnostic.detail
