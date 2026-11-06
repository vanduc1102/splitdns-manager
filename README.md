# SplitDNS Manager

A small native macOS app for managing **split DNS**: it lists, adds, edits and removes the files in `/etc/resolver`, so lookups for one domain (say `corp.example.com`) go to a specific name server while everything else keeps using your normal DNS.

It is a GUI for the usual shell helpers:

| Shell | App |
| --- | --- |
| `resolver-add corp.example.com 10.0.0.53` | **New Resolver…** (⌘N) |
| `resolver-rm corp.example.com` | **Remove** (⌫ or the toolbar) |
| `resolver-ls` | the sidebar |
| `sudo killall -HUP mDNSResponder` | **Flush DNS Cache** (⌥⌘F), also done after every change |

## Install

Download `SplitDNSManager-<version>.dmg` from the [Releases](../../releases) page, open it and drag the app to **Applications**. Compare the download with `SHA256SUMS` if you like. It needs macOS 14 or later and runs natively on Apple silicon and Intel.

Releases are signed and notarized when the maintainer has configured the [signing secrets](#signing-and-notarization). Otherwise the app is only ad-hoc signed and Gatekeeper blocks it on first launch. Either:

- open **System Settings › Privacy & Security** and click **Open Anyway** (macOS 14: right-click the app and choose **Open**), or
- run `xattr -dr com.apple.quarantine "/Applications/SplitDNS Manager.app"`.

## Using it

- Each file in `/etc/resolver` is one **domain** routed to one to three **name servers**, with an optional **port**.
- A status next to every domain compares the file with what macOS has loaded (`scutil --dns`): *Active*, *Active but unreachable* (VPN off?), *Loaded with different name servers*, *Not loaded* or *Status unavailable*.
- Every change asks for your administrator password. macOS names the dialog after `osascript`, which is how the change is run.
- Lines the app does not model (comments, `search_order`, …) are kept and written back after the managed lines.
- Symbolic links, for example from nix-darwin, are shown read-only. They can still be removed, which deletes only the link.

## How it works

Reading `/etc/resolver` needs no privileges. To change it, the app builds a short `/bin/sh` script from validated, shell-quoted values and runs it with `osascript` (`do shell script … with administrator privileges`), which is what shows the password prompt. A save writes a temporary file and renames it into place, so macOS never sees a half-written resolver. Then it runs `dscacheutil -flushcache` and `killall -HUP mDNSResponder`. There is no helper tool and no background process.

## Build from source

You need macOS 14+ and a Swift 6 toolchain (Xcode 16+ or the Command Line Tools).

```sh
make test              # unit tests
make lint              # swift format lint, plus shellcheck if installed
make format            # format the sources in place
make run               # build dist/"SplitDNS Manager.app" (ad hoc signed) and open it
make dmg VERSION=1.2.3 # also build the .dmg and .zip in dist/
```

`Scripts/package-app.sh` and `Scripts/package-dmg.sh` read these variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `VERSION` | `0.0.0-dev` | `1.2.3` or `1.2.3-rc.1`; sets the version and the file names |
| `BUILD_NUMBER` | `1` | `CFBundleVersion` |
| `BUNDLE_ID` | `io.github.vanduc1102.splitdns-manager` | bundle identifier |
| `ARCHS` | `arm64 x86_64` | architectures of the universal binary |
| `CODESIGN_IDENTITY` | `-` | signing identity; `-` signs ad hoc |

Development notes:

- With only the Command Line Tools installed, `make test` adds the `-plugin-path` that Swift Testing needs. A full Xcode needs no flag.
- The Command Line Tools also lack SwiftUI's `@State` macro, so the code avoids `@State`; the `@Observable` view model is held in a plain `let`.
- `SplitDNSCore` has no UI and holds all the logic; the tests use temporary directories and never touch the real `/etc/resolver`.
- Regenerate the icon with `make icon`.

## Continuous integration

| Workflow | Runs on | What it does |
| --- | --- | --- |
| [Verify PR](.github/workflows/pull-request.yml) | pull requests to `main` | `swift format` lint, shellcheck and actionlint, then the build below, without any secrets |
| [Build](.github/workflows/build.yml) | pushes to `main`, manual runs, and reused by the other two | runs the tests, builds the universal app, `.dmg`, `.zip` and `SHA256SUMS`, and uploads them as the `SplitDNSManager` artifact for 14 days |
| [Release](.github/workflows/release.yml) | tags `v*.*.*` | the build with signing and notarization, then creates the GitHub release |

Third-party actions are pinned to commit SHAs and updated weekly by Dependabot. Each job that needs macOS uses the `macos-26` runner.

### Releasing

```sh
git tag v1.2.3
git push origin v1.2.3
```

The release gets the `.dmg`, the `.zip`, `SHA256SUMS` and generated notes. A tag with a suffix, such as `v1.2.3-rc.1`, is marked as a pre-release. To try the signing pipeline without a release, run **Build** from the Actions tab with a `version` and **release** ticked.

### Signing and notarization

Add these repository secrets to sign with a Developer ID and notarize. Without them, release builds fall back to ad-hoc signing and the run shows a warning.

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | your exported *Developer ID Application* certificate with its private key, as base64: `base64 -i DeveloperID.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | the password you set when exporting the `.p12` |
| `NOTARY_APPLE_ID` | the Apple ID of the developer account |
| `NOTARY_TEAM_ID` | the ten character team ID |
| `NOTARY_PASSWORD` | an [app-specific password](https://support.apple.com/102654) for that Apple ID |

## Layout

```
Sources/SplitDNSCore/      parsing, validation, script building, the privileged runner, the view model
Sources/SplitDNSManager/   the SwiftUI app
Tests/SplitDNSCoreTests/   unit tests (Swift Testing)
Packaging/                 Info.plist template and AppIcon.icns
Scripts/                   package-app.sh, package-dmg.sh, notarize.sh, generate-icon.swift
.github/                   workflows and Dependabot configuration
```
