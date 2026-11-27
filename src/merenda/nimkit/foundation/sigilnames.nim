from sigils/protocol import SigilName, sigName

template sigils*(name: static string): SigilName =
  ## Construct a SigilName from a literal using Sigils' active representation.
  sigName(name)
