# Release Checklist

LinguistMac has two artifact paths:

- unsigned development artifacts for local or CI smoke testing
- signed and notarized release artifacts after Developer ID credentials are
  configured

Unsigned artifacts are not public releases.

## Unsigned Dry Run

Run:

```sh
./script/package_release.sh unsigned
```

Expected outputs:

- `dist/release/LinguistMac-unsigned.zip`
- `dist/release/LinguistMac-unsigned.dmg`

Use this path for CI artifact checks and local release rehearsal. It proves the
archive/package layout is reproducible, but it does not prove Gatekeeper release
readiness.

## Signed And Notarized Release

Required local environment:

- `DEVELOPER_ID_APPLICATION`: Developer ID Application certificate name
- `NOTARY_KEYCHAIN_PROFILE`: notarytool keychain profile name, optional only
  when doing a signed build without notarization

Run:

```sh
./script/package_release.sh signed
```

The script:

- builds `LinguistMac.app` in Release configuration
- signs the app with hardened runtime and app entitlements
- verifies the signature
- creates zip and DMG artifacts
- submits the zip for notarization when `NOTARY_KEYCHAIN_PROFILE` is set
- staples and validates the app after notarization
- runs Gatekeeper assessment for signed artifacts

## GitHub Actions Secrets

The `Release Artifact` workflow supports `workflow_dispatch` with `unsigned` or
`signed` mode.

For signed mode, configure these repository secrets:

- `DEVELOPER_ID_APPLICATION`
- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_KEYCHAIN_PASSWORD`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`

Do not commit certificates, private keys, API keys, or notary credentials.

## Pre-Release Review

- Confirm `Configuration/LinguistMac/Info.plist` version and build number.
- Confirm `Configuration/LinguistMac/LinguistMac.entitlements` matches the
  current permission model.
- Run the local CI parity commands in `docs/ci-cd.md`.
- Run `./script/package_release.sh unsigned` before trying a signed release.
- Run `./script/package_release.sh signed` only after Developer ID and
  notarization secrets are configured.
- Review `docs/privacy.md` for any behavior changed since the last release.
