# Signed in-app updates

ExeRunner 0.6.0 introduces manual updates via Sparkle **2.10.0**, pinned at upstream
commit `eef1a539a373c1f1a320624b1130fc5de7b2e100` in `app/Package.resolved`.
SwiftPM verifies the binary artifact checksum declared by that package. The versioned
framework, XPC services and updater helpers keep upstream signatures. The app adds
`@executable_path/../Frameworks` to its runtime search paths. The clean release's
Mach-O/dependency/deployment-floor check includes all embedded helpers.

## Trust and privacy

- Feed: `https://raw.githubusercontent.com/mmd-art/exerunner/main/updates/appcast.xml`.
- Archive URLs use immutable GitHub release tags, not GitHub's `latest` endpoint
  (which excludes prereleases).
- The app pins an Ed25519 public key in `SUPublicEDKey`. `SURequireSignedFeed` and
  `SUVerifyUpdateBeforeExtraction` require signed metadata and verify payloads before
  extraction. Never add an unsigned fallback or make the production feed configurable
  through launch arguments.
- The production private key is kept in the publisher's login Keychain under Sparkle
  account `local.exerunner.app`. It is never exported into the repository or release.
- No background update checks, automatic downloads, hardware-profile submission or
  automatic silent installation are enabled. Clicking Check for updates contacts
  GitHub, which necessarily receives the normal network request/IP address.
- Sparkle replaces the app bundle, not Application Support, environments, saves or
  game files. Close Windows programs before updating. Busy checks cover GUI launches,
  live clients/servers, component installs, installers and save operations. A staged
  installation remains guarded after the checking session ends and across an unchanged
  app build's restart. Launch actions are blocked during the final reserved restart.
- EdDSA signing is separate from Apple Developer ID and notarization. This alpha remains
  ad-hoc signed and not notarized; do not describe it as Apple-approved.

## Publishing

1. Review changes, run regression checks, then commit the candidate. Build with
   `scripts/build-app.sh release --without-d3dmetal`, reusing a verified engine.
2. Test a fresh profile and create `scripts/make-dmg.sh`. Retain one current DMG,
   matching corresponding-source archive and checksums; do not copy test profiles.
3. With official pinned Sparkle tools, sign the DMG using
   `sign_update --account local.exerunner.app <dmg>`. Put its signature, exact length,
   actual CFBundleVersion and immutable release URL in the appcast enclosure. Set
   minimumSystemVersion to the tested deployment floor.
4. Sign the XML feed itself using `sign_update --account local.exerunner.app updates/appcast.xml`.
   Verify the archive and feed with `--verify`. Any later XML edit requires re-signing.
5. Upload release assets, verify remote digests/downloads, then publish the signed feed
   to main. Never publish a feed pointing to an unavailable asset. The feed commit may
   follow the binary's source commit; the app's ExeRunnerSourceRevision records the latter.
6. Preserve the Keychain signing key. A release from a different key cannot update
   existing installs; key rotation needs a separately reviewed migration.

## Verification

`tests/updater-integration-test.sh` links the production AppUpdater delegate into a
small disposable AppKit host. A temporary test key and localhost feed are confined to
the managed test root. The actual Sparkle downloader/installer replaces version 1 with
2 and relaunches it; busy and staged-termination checks run on synthetic state. A
modified archive must be rejected before extraction. No owner application is replaced.
This does not prove an M1 Pro recipient's Gatekeeper state, network environment or NX
compatibility. `tests/fresh-profile-test.py` separately checks the actual release app's
empty-profile first launch and native close.

## Developer scratch lifecycle on the owner's Mac

The existing `tools/artifacts.py run` entrypoint delegates new commands to the owner's
shared `managed_job.py` when present. `tools/managed-artifact-command.py` places compiler
caches and fixtures below that runner's private TMPDIR without replacing TMPDIR/TMP/TEMP.
Nested verification reuses the same admitted context, not another resource gate. The
context is validated separately from legacy ExeRunner leases. Native release outputs
remain at their documented build paths; only disposable compiler/test scratch belongs
to the outer runner. Its final removed/PRESERVED receipt is required before claiming
cleanup. Existing retained engine/rollback and owner runtime caches are separate.
