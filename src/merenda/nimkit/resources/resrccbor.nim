## CBOR encoding and decoding for NimKit resource bundles.

import cborious

import ./resrccore

const
  ResourceEncodingMode =
    {CborObjToMap, CborCanonical, CborEnumAsString, CborCheckHoleyEnums}
  ResourceDecodingMode = {CborObjToMap, CborEnumAsString, CborCheckHoleyEnums}

proc encodeResourceBundle*(bundle: ResourceBundle): string =
  ## Encodes a bundle as deterministic, canonical CBOR maps.
  toCbor(bundle, ResourceEncodingMode)

proc addEnvelopeDiagnostics(result: var ResourceLoadResult) =
  if result.bundle.format != ResourceFormatName:
    result.diagnostics.add(
      rdsError,
      "resource.format.unsupported",
      "unsupported resource format '" & result.bundle.format & "'",
      path = "format",
    )
  if result.bundle.version.major != CurrentResourceVersion.major:
    result.diagnostics.add(
      rdsError,
      "resource.version.incompatible",
      "resource major version " & $result.bundle.version.major &
        " is incompatible with supported version " & $CurrentResourceVersion.major,
      path = "version.major",
    )
  elif result.bundle.version.minor > CurrentResourceVersion.minor:
    result.diagnostics.add(
      rdsWarning,
      "resource.version.newerMinor",
      "resource minor version " & $result.bundle.version.minor &
        " is newer than supported version " & $CurrentResourceVersion.minor,
      path = "version.minor",
    )

proc decodeResourceBundle*(
    data: sink string, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Decodes resource data without constructing any identity-bearing objects.
  if data.len > limits.maximumDataBytes:
    result.diagnostics.add(
      rdsError, "resource.data.tooLarge",
      "resource data exceeds the configured byte limit",
    )
    return

  try:
    let dataLength = data.len
    var stream = CborStream.init(data)
    stream.encodingMode = ResourceDecodingMode
    stream.setPosition(0)
    result.bundle = stream.unpack(ResourceBundle)
    if stream.getPosition() != dataLength:
      result.diagnostics.add(
        rdsError, "resource.cbor.trailingData", "resource CBOR contains trailing data"
      )
    result.addEnvelopeDiagnostics()
  except CatchableError as error:
    result.diagnostics.add(
      rdsError, "resource.cbor.invalid", "could not decode resource CBOR: " & error.msg
    )

proc loadResourceBundle*(
    path: string, limits = initResourceLoadLimits()
): ResourceLoadResult =
  ## Reads and decodes a bundle. File and CBOR failures are returned as diagnostics.
  try:
    result = decodeResourceBundle(readFile(path), limits)
  except CatchableError as error:
    result.diagnostics.add(
      rdsError,
      "resource.file.unavailable",
      "could not read resource file '" & path & "': " & error.msg,
      path = path,
    )
