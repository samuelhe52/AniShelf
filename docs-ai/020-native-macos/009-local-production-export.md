# 020.009 — Local production macOS export

## Context

On 2026-10-18 the maintainer requested a local release-testing app with production
APNs and CloudKit environments, without uploading the app for notarization or
store distribution. The existing `release-testing-mac` target exported an App Store
package and extracted its app. Signed entitlements contained the requested values,
but the installed app failed to launch.

Verified runtime evidence: `taskgated-helper` rejected the embedded Mac Team Store
profile, reported no eligible provisioning profiles, and `amfid` reported error
`-413`, "No matching profile found". Static signature verification had passed;
that check did not establish local launch eligibility. Logs were inspected locally
and are not retained as repository evidence.

## Planned correction

- Keep one `release-testing-mac` target and the existing local app output location.
- Change `scripts/ReleaseTestingMacExportOptions.plist` to `method=developer-id`,
  retaining `destination=export` and `iCloudContainerEnvironment=Production`.
- Copy the exported app directly rather than unpacking an App Store package.
- Verify the exported signature, sandbox, and production APS/CloudKit entitlements.
- Replace the failed installed app only after checking the new artifact. Preserve
  the old app outside the repository until launch verification succeeds.
- Verify local launch using an isolated library fixture. Actual production
  CloudKit sync and notification delivery remain separate acceptance checks.

Developer ID signing and notarization are separate operations. This target must
not submit the app to a notary service or App Store Connect. Xcode may contact
Apple to obtain the Developer ID provisioning profile needed for CloudKit/APNs.

## Alternatives and decisions

| Alternative | Reason |
| --- | --- |
| Continue extracting the App Store package | Rejected: launch failure is the profile/signing route, not package extraction or executable permissions. |
| Development export | Does not satisfy the requested production APNs requirement. |
| Developer ID with a separate notarization submission | Unnecessary for this local test workflow and outside the requested no-upload scope. |
| Change Gatekeeper settings or remove capabilities | Would not fix the rejected provisioning profile while retaining the required capabilities. |

## Refs

- `Makefile`, `scripts/ReleaseTestingMacExportOptions.plist`.
- [Apple: distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/).
- [Apple: Developer ID capabilities and profile validity](https://developer.apple.com/help/account/certificates/certificates-overview/).
- [Apple: archive export followed by a separate notary submission](https://developer.apple.com/documentation/security/customizing-the-xcode-archive-process).

## Outcome and validation (2026-10-18)

Implemented in `Makefile` and `scripts/ReleaseTestingMacExportOptions.plist`.
The target verifies the code signature and requires production APNs, production
CloudKit, and App Sandbox before copying the exported app into the local app
output directory. The earlier `make clean` change removing the root build
artifacts remains in the Makefile.

- `plutil -lint`, the Makefile dry run, and `git diff --check` passed.
- A fresh `make release-testing-mac` archive and local export passed. No notary
  submission command ran. The export produced an app directly, not a package.
- The app is signed by `Developer ID Application: Samuel He (768QBKMWKW)` and
  embeds `Mac Team Direct Provisioning Profile: com.samuelhe.MyAnimeList`.
  The profile permits all devices and production APNs.
- Signed entitlements show `com.apple.developer.aps-environment=production`,
  `com.apple.developer.icloud-container-environment=Production`, and
  `com.apple.security.app-sandbox=true`. Strict recursive signature verification
  passed before and after installation.
- The failed App Store-signed app was preserved in a temporary backup, and the
  corrected app was installed into `/Applications`. `open` succeeded; the installed
  executable stayed running, and accessibility inspection showed its library
  window. No Gatekeeper protection was disabled or bypassed.
- `make clean` passed after installation, removing the root build outputs.
  Project-specific DerivedData was then removed. The installed app remained
  running, and the previously exported IPA on the Desktop was preserved.

The planned isolated-fixture launch was unavailable in an ordinary Release build:
fixtures compile only with `DEBUG` or `LIBRARY_FIXTURES`. Validation therefore used
normal startup of the requested production app without changing compilation
flags. Startup logged an expired CloudKit change token and reset it for a refetch.
This launch check does not establish sync completion, APNs delivery, or full UI
acceptance. An initially broad process check also matched an unrelated simulator
instance; it was left alone, and installation checks were restricted to the native
macOS executable path.
