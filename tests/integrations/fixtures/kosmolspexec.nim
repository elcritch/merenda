## Dispatch the TCP LSP child before any integration suites run.
import std/os
import merenda/kosmo/[cli, lsptcp]

if paramCount() == 2 and paramStr(1) == KosmoLspExecFlag:
  when defined(posix):
    execLspServer(@[paramStr(2)])
  else:
    runLspTcpChild(paramStr(2))
