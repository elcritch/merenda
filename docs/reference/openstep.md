# OpenStep Reference Documents

These are useful OpenStep sources found online. The original PDFs are not
vendored here because their notices do not grant general redistribution rights.

## Primary Specification

- **OpenStep Specification**, October 19, 1994
  - HTML: <https://www.gnustep.org/resources/OpenStepSpec/OpenStepSpec.html>
  - PDF mirror: <https://levenez.com/NeXTSTEP/OpenStepSpec.pdf>
  - Alternate PDF mirror:
    <https://www.nextcomputers.org/NeXTfiles/Docs/Software/OPENSTEP/openstep_spec.pdf>

The specification covers the Application Kit, Foundation Kit, and Display
PostScript portions of the OpenStep API. Its copyright notice allows one
downloaded copy for study only and says no API implementation license is
granted or implied.

## Interface Guidelines

- **OpenStep User Interface Guidelines**, Revision A, September 1996
  - PDF: <https://www.gnustep.org/resources/documentation/OpenStepUserInterfaceGuidelines.pdf>

This Sun/NeXT manual is useful for control, menu, panel, window, keyboard, and
mouse behavior. Its copyright notice restricts copying and reproduction, so do
not commit the PDF to this repository without separate permission.

## Related GNUstep References

- GNUstep documentation index:
  <https://www.gnustep.org/resources/documentation/>
- GNUstep OpenStep story:
  <https://www.gnustep.org/information/openstep.html>
- GNUstep GUI OpenStep compliance:
  <https://www.gnustep.org/resources/documentation/Developer/Gui/General/OpenStepCompliance.html>
- GNUstep Base OpenStep compliance:
  <https://www.gnustep.org/resources/documentation/Developer/Base/General/OpenStepCompliance.html>

## Local Study Copies

The OpenStep Specification notice permits one downloaded copy for study. If a
local study copy is needed, keep it under `docs/reference/`, where downloaded
PDFs are ignored:

```sh
nim download_references
```

The UI guidelines PDF has a stricter reproduction notice; use the hosted link
unless separate permission is available.
