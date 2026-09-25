--path:
  "../src"
--define:
  "figdraw.vulkanReadback"
--define:
  "nimkitIgnoreEnvOverrides"
--define:
  "merendaTests"

when defined(nimkitSanitizers):
  switch("debugger", "native")
  switch("define", "noSignalHandler")
  switch("define", "useMalloc")
  switch("passC", "-fsanitize=address,undefined -fno-omit-frame-pointer")
  switch("passL", "-fsanitize=address,undefined")
