## Public Kosmo API and standalone application entry point.

import ./[application, runner]

export application except runKosmoRequest
export runner except runKosmoMain

when isMainModule:
  runKosmoMain()
