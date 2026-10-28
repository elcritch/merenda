# Releasing Kosmo binaries

The `release-kosmo` GitHub Actions workflow builds these artifacts:

- `kosmo-linux-amd64.tar.gz`
- `kosmo-linux-amd64-musl.tar.gz`
- `kosmo-linux-arm64.tar.gz`
- `kosmo-freebsd-amd64.tar.gz`
- `kosmo-macos-arm64.zip`, containing `Kosmo.app`
- `kosmo-windows-amd64.zip`
- `SHA256SUMS.txt`

Each executable archive also includes the notices for Kosmo's bundled IBM Plex
Sans and JetBrains Mono Nerd Font Mono resources. On macOS the notices live in
the app's `Contents/Resources` directory.

macOS bundles minimal HarfBuzz and FriBidi libraries built for macOS 13 in
`Contents/Frameworks`, with their notices in `Contents/Resources/text-library-licenses`.
Windows archives place the text DLLs beside `kosmo.exe`; the installer copies
them together and installs their notices with the font notices. Regular Linux
and FreeBSD builds discover system HarfBuzz and FriBidi libraries at runtime.
The Linux amd64 musl build compiles and links both text libraries statically
with `-d:harfbuzzyStatic`. The local macOS installer uses the same shared-library
build and bundling scripts as macOS CI, including runtime paths into
`Contents/Frameworks`, text-library notices, and library code signatures.

For regular Linux builds, install the runtime libraries with `sudo apt install
libharfbuzz0b libfribidi0` on Debian/Ubuntu, `sudo pacman -S harfbuzz fribidi`
on Arch, or `sudo dnf install harfbuzz fribidi` on Fedora.
Debian 12 provides HarfBuzz 6, so its amd64 users can choose `--static` for
shaping with the bundled newer library.

Shared builds use FigDraw 0.46.3's runtime backend selection: when HarfBuzz 7
or newer and FriBidi are available, Kosmo enables shaping and automatic
system-font fallback. Missing or unsupported text libraries select Pixie
instead. macOS and Windows still bundle the shared libraries to provide shaping
without a separate installation. `-d:harfbuzzDynlib` selects the bundled HarfBuzz
path, and `-d:harfbuzzyFribidiDynlib` selects FriBidi.

The five bundled Moe themes are embedded in the executable and installed into
Kosmo's platform asset cache for Moe's file-based theme loader. Release archives
do not need a separate `data/moe/themes` directory, and theme discovery does not
depend on the working directory used to launch Kosmo.

Release executables retain native debug information and link the `libbacktrace`
stack-trace override. Windows CI and releases use MinGW-w64 GCC from MSYS2's
UCRT64 environment, with HarfBuzz and FriBidi built for the same environment.
Windows archives include the text DLLs, their transitive dependencies, and their
license notices beside `kosmo.exe`. The executable retains DWARF symbols;
there is no separate PDB. Release checks inspect its debug information and
`libbacktrace` symbols, test stack traces and concurrent ownership, and launch
Kosmo with build-tool directories removed from `PATH`.
Kosmo links its MinGW GCC, C++ and threading runtimes statically; release CI
checks that the executable does not import their DLLs. The shared text libraries
can still require MinGW runtime DLLs, which the bundler copies beside the executable.

Nim's instrumented stack tracing remains disabled for these builds because
`libbacktrace` uses the compiler's native debug information without its runtime
overhead. `libbacktrace` is an unconditional package dependency. The project
configuration imports it except for manually selected Windows/MSVC builds.

Linux keeps the debug information in the executable. The macOS app
bundles its matching symbols at
`Contents/MacOS/kosmo.dSYM`. This is the location libbacktrace checks beside the
running executable, so release stack traces retain file and line information.
LLDB can load the same symbols explicitly with
`target symbols add /path/to/Kosmo.app/Contents/MacOS/kosmo.dSYM`.

The root `install.sh` downloads the archive for the current operating system and
architecture, verifies it against `SHA256SUMS.txt`, and installs it without root
access. Its defaults are `~/.local/bin` on Linux and Windows, and
`~/Applications/Kosmo.app` plus a `~/.local/bin/kosmo` command link on macOS.
`KOSMO_INSTALL_DIR`, `KOSMO_BIN_DIR` (macOS), and `KOSMO_DOC_DIR` (Linux, FreeBSD,
and Windows) override those destinations. `KOSMO_VERSION` selects a release tag;
when unset, the installer downloads the latest release.
On Linux amd64, pass `--static` to install `kosmo-linux-amd64-musl.tar.gz`, the
statically linked musl variant.

Publishing a GitHub release runs all platform builds and uploads the resulting archives
to that release. Linux, FreeBSD, and macOS publish as soon as those builds finish,
without waiting for Windows. A separate job adds the Windows archive when it is
ready and updates the shared `SHA256SUMS.txt` while preserving the other checksums.
The Linux amd64 musl build is statically linked for the C runtime; the
other Linux and FreeBSD builds use their platform's shared system libraries. The
release tag should use the `vX.Y.Z` form; the version without the `v` is embedded in the
executable and the macOS bundle.

The workflow can also be run manually. Manual runs upload Actions artifacts without
modifying a GitHub release. As a temporary release-repair exception, every push to
`ci/update-release-binaries` embeds version `0.17.0` and replaces the assets on the
existing `v0.17.0` release. Remove that branch/tag exception after release testing.
Published and ordinary manual macOS builds are currently ad-hoc signed for CI
validation only. They include the `com.apple.security.get-task-allow` entitlement so
LLDB can attach after Developer Tools access is enabled on the Mac. Select
`notarize_macos` on a manual run to test the disabled Developer ID signing and
notarization path while it is being repaired. The notarized artifact omits
`get-task-allow` because Apple's notary service rejects that entitlement.
Because an ad-hoc-signed app can be rejected when a browser marks it as
quarantined, direct browser downloads are not a substitute for notarized
distribution. Use the checksum-verifying `install.sh` path for these temporary
releases.

## macOS signing requirements

Gatekeeper-compatible distribution outside the Mac App Store requires a Developer ID
Application signature and Apple notarization. Apple issues Developer ID certificates
only to members of the Apple Developer Program or Apple Developer Enterprise Program.
The standard program currently costs 99 USD per membership year. Open-source projects
do not receive an automatic waiver; Apple limits fee waivers to qualifying nonprofit
organizations, accredited educational institutions, and government entities.

Kosmo does not need an App Store listing, installer certificate, provisioning profile,
or paid-app agreement. The workflow has an opt-in path that signs with the hardened
runtime and a secure timestamp, submits the app with `notarytool`, and staples it before
creating the final ZIP. Published releases temporarily skip that path and use an ad-hoc
signature with `get-task-allow` instead.

Apple references:

- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple Developer Program membership](https://developer.apple.com/programs/whats-included/)
- [Membership fee waivers](https://developer.apple.com/help/account/membership/fee-waivers)

## Repository secrets

Create a **Developer ID Application** certificate in Certificates, Identifiers &
Profiles. Install the certificate locally together with its private key, export both as
a password-protected PKCS#12 (`.p12`) file, and base64-encode that file as one line.

Configure these GitHub Actions repository secrets:

- `APPLE_DEVELOPER_ID_P12_BASE64`: base64-encoded `.p12` contents
- `APPLE_DEVELOPER_ID_P12_PASSWORD`: password used when exporting the `.p12`
- `APPLE_ID`: Apple Account email used for notarization
- `APPLE_TEAM_ID`: ten-character Developer Program team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for `notarytool`

When `notarize_macos` is selected on a manual run, the workflow imports the certificate
into an ephemeral keychain, derives the signing identity from the imported Developer ID
certificate, and deletes the keychain at the end of the job. That opt-in run fails before
building the app if any required credential is absent. Normal published releases do not
read these secrets while Developer ID signing is disabled.
