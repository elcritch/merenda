# Kosmo build and symbolication review

## Speed optimization

Changed all six Kosmo release builds (including FreeBSD and both Windows
renderer variants) and the local macOS installer from `--opt:size` to
`--opt:speed`, as requested. Kept the C backend and native debug-information
settings. This prioritizes runtime speed; the prior 30.42 MB size baseline
must not be presented as the size of the new configuration.

Validation: checked all packaging compiler invocations and shell syntax of
`packaging/macos/install-local.sh`. A complete speed build is recorded below
when available.

## Symbolication experiment before implementation

The previous size-optimized macOS arm64 executable was 30,419,736 bytes.
`strip -S -x` reduced a disposable copy to 16,687,848 bytes. After ad-hoc
hardened-runtime signing with the existing debug entitlements it was
16,706,592 bytes. Its 11,009,892 machine-code bytes had the same SHA-256 before
and after stripping/signing. UUID matching, signature verification, and
`--help` passed. The installed application was not changed.

LLDB and `atos` resolved addresses from the stripped Kosmo to `runner.nim`
and `kosmo.nim` using the saved matching dSYM. A small libbacktrace reproduction
produced identical function names and source lines before and after stripping
when a matching dSYM was beside it. Without the dSYM, even the original
unstripped reproduction produced no frames. Keeping local symbol names alone
did not preserve the in-process trace in that experiment.

Controlled SIGABRT tests in full Kosmo produced incomplete or incorrectly
named in-process frames in both the original and stripped executables. They
do not establish equivalent full crash-report quality. External symbolication
worked, but these in-process results require further investigation.

Generating another dSYM later from the reused compiler cache emitted object
timestamp mismatch warnings. Those results were discarded; tests used the
dSYM saved with the original executable. Generate and archive symbols before
reusing the cache. The original dSYM's DWARF file is 74,874,016 bytes, so moving
debug files out of the executable does not make their separate storage free.

Logs, binaries, and the small reproduction are under
`/tmp/kosmo-symbolication-check/`. The original matching pair is
`/tmp/kosmo-size-rchan-final` and `/tmp/kosmo-size-rchan-final.dSYM`.

## Raw trace prototype — unfinished

`src/merenda/nativestacktraces.nim` wraps the existing libbacktrace override.
The experimental `-d:merendaRawStackTraces` option prints raw frames instead
of resolving names in-process. Development mode retains the existing resolver
and falls back to raw frames if it returns no entries. Release compiler
invocations do **not** enable the option yet, and no symbol stripping or
separate-symbol packaging has been added.

Each raw frame contains the OS/architecture, runtime program counter, image
load base, an address adjusted for the symbol file, image identity, and path.
The small C helper reads loaded-image metadata:

- macOS: Mach-O UUID and preferred `__TEXT` address.
- Linux/FreeBSD: ELF load bias and GNU build ID, when present.
- Windows: PE preferred image base and CodeView identifier/age, with a
  timestamp/image-size fallback when CodeView metadata is absent. That fallback
  is not a strong unique build identity; release packaging still needs a
  reliable identifier and artifact manifest.

Windows releases currently use MinGW/DWARF, not MSVC/PDB. Keep that existing
toolchain. The manual Windows/MSVC configuration still uses Nim's instrumented
traces and bypasses this wrapper.

Validation so far:

- Compiled and ran the raw fixture on macOS arm64, Nim 2.4.0, ARC,
  `--exceptions:goto`, `--opt:speed`; live frames contain addresses and UUIDs.
- Compiled the C helper with `-Wall -Wextra -Werror` using Apple Clang and the
  installed x86_64 MinGW cross-compiler. Windows execution has not been tested.
- A Linux Docker environment with Nim and GCC is available, but Linux runtime
  checks have not been run yet.
- A fixture assertion initially assumed its executable name was fixed;
  corrected it to use the actual executable basename.

**Open issue:** the explicit `getStackTrace()` probe prints raw frames, but an
unhandled exception in the same fixture still prints only its error message.
This also occurred with the original libbacktrace reproduction. Generated C
shows pending goto-exception checks interrupting some formatting calls.
Removing checked formatting calls and disabling checks/assertions inside the
new callbacks did not resolve the complete unhandled-exception path. Do not
claim this prototype handles all crashes or enable stripped releases before
testing and resolving that path. Caught exceptions, signals, and deep stacks
also need coverage. The wrapper still uses libbacktrace's existing counter
capture and its depth limit.

The platform helper uses loader APIs and the Nim wrapper allocates strings;
this is not a new async-signal-safe crash handler. It preserves the existing
best-effort libbacktrace model. Frames in system/shared libraries require those
libraries' matching symbols, not just Kosmo's debug file.

## Resume checklist

1. Complete raw-trace tests for explicit traces, caught/unhandled exceptions,
   signals, missing debug files, deep stacks, and ASLR; verify source recovery
   against the saved exact-build artifact on each supported platform.
2. Add automated packaging round-trip checks on macOS, Linux, and Windows.
   Keep full-suite tests in their existing shared runners; the strip fixture
   requires its own process and compilation settings.
3. Archive matching dSYMs or DWARF files with binary identity/checksum manifests,
   then strip runtime executables. Strip macOS before signing. Decide where the
   local installer retains symbols; its temporary build directory is deleted.
4. Enable raw traces in release builds only after validation, update release
   artifact uploads/checksums and symbolication instructions, and rebuild Kosmo
   with speed optimization to measure the final result.

The full Merenda suite against PR #64 is a separate baseline run, using
Merenda a160f21c and Sigils 0abe4cc in an isolated copy of the Atlas dependencies.
It does not validate this prototype. Its subagent will preserve logs outside
the checkout and remove that checkout when done.
