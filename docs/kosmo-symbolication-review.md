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
