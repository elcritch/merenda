# Releasing Kosmo binaries

The `release-kosmo` GitHub Actions workflow builds these artifacts:

- `kosmo-linux-amd64.tar.gz`
- `kosmo-macos-arm64.zip`, containing `Kosmo.app`
- `kosmo-windows-amd64.zip`
- `SHA256SUMS.txt`

Each platform archive also includes the notices for Kosmo's bundled IBM Plex
Sans and JetBrains Mono Nerd Font Mono resources. On macOS the notices live in
the app's `Contents/Resources` directory.

Publishing a GitHub release runs all three builds and uploads the resulting archives to
that release. The release tag should use the `vX.Y.Z` form; the version without the `v`
is embedded in the executable and the macOS bundle.

The workflow can also be run manually. Manual runs upload Actions artifacts but do not
modify a GitHub release. By default, a manual macOS build is ad-hoc signed for CI
validation only. Select `notarize_macos` to test the complete release-signing path.

## macOS signing requirements

Gatekeeper-compatible distribution outside the Mac App Store requires a Developer ID
Application signature and Apple notarization. Apple issues Developer ID certificates
only to members of the Apple Developer Program or Apple Developer Enterprise Program.
The standard program currently costs 99 USD per membership year. Open-source projects
do not receive an automatic waiver; Apple limits fee waivers to qualifying nonprofit
organizations, accredited educational institutions, and government entities.

Kosmo does not need an App Store listing, installer certificate, provisioning profile,
or paid-app agreement. It currently uses no restricted entitlements. Its release app is
signed with the hardened runtime and a secure timestamp, submitted with `notarytool`,
and stapled before the final ZIP is created.

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

The workflow imports the certificate into an ephemeral keychain, derives the signing
identity from the imported Developer ID certificate, and deletes the keychain at the end
of the job. Published releases fail before building the app if any required credential
is absent; they never fall back to an ad-hoc signature.
