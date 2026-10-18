## Standalone native MSVC regression for linker commands over Windows' limit.

when isMainModule:
  when not (defined(windows) and defined(vcc)):
    {.error: "Compile this fixture for Windows with --cc:vcc".}

  const linkerOptions = block:
    var options = "/link"
    # Repeating a harmless warning option forces a response file. vccexe used
    # to expand it again and exceed CreateProcess's 32,767-character limit.
    for i in 0 ..< 3000:
      options.add " /IGNORE:4099"
    options

  {.passL: linkerOptions.}
  echo "MSVC linked successfully with a response file over 32K"
