## Child mode for bounded background-command output tests.
import std/[os, strutils]

const backgroundCommandProbe* = "--merenda-background-command-probe"

if paramCount() == 2 and paramStr(1) == backgroundCommandProbe:
  let mode = paramStr(2)
  for index in 0 ..< 32:
    if mode in ["stdout", "both"]:
      stdout.write("a".repeat(8192))
      stdout.flushFile()
    if mode in ["stderr", "both"]:
      stderr.write("b".repeat(8192))
      stderr.flushFile()
  quit(0)
