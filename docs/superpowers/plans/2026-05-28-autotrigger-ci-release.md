# AutoTrigger CI + Release (T6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. NOTE: this is **infrastructure**, not TDD — there is no red-green loop. "Verify" steps are real commands (CI run, `stapler validate`, `spctl`), not unit tests.

**Goal:** Continuous test on every push, and a tag-triggered release pipeline that builds, Developer-ID-signs, notarizes, staples, packages a DMG, and publishes it to GitHub Releases.

**Architecture:** Two GitHub Actions workflows on a macOS runner. `ci.yml` runs `swift build` + `swift test` on every push/PR (works today against the existing package). `release.yml` runs on a version tag: it builds the distributable `.app`, signs with the Developer ID Application cert, notarizes via `notarytool`, staples, makes a DMG, and uploads it. The release stage is wired and parameterized now but only fully runs once the menubar **app target** exists (it produces the `.app`).

**Tech Stack:** GitHub Actions (`macos-14` runner), Xcode toolchain, `codesign`, `xcrun notarytool`, `xcrun stapler`, `hdiutil`, `gh` / `softprops/action-gh-release`.

**Depends on:** the menubar **app target** (separate plan) for the release stage's `.app`. The CI test stage depends on nothing — it runs now.

**Distribution decision (from design doc):** NOT Mac App Store (sandbox blocks reading system-wide launchd/cron). Direct download, Developer ID signed + notarized.

---

### Task 1: CI test workflow (runs now)

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app
      - name: Swift version
        run: swift --version
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

- [ ] **Step 2: Verify (real, not a unit test)**

Commit + push to a branch and open a PR. Confirm the `CI / test` check goes green on GitHub. If `swift test` fails on the runner but passes locally, check the Xcode/Swift version line matches your local toolchain (Swift 6.3).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run swift build + test on push and PR"
```

---

### Task 2: Secrets setup (documented, one-time)

These secrets must exist in the GitHub repo before `release.yml` can sign/notarize. This task produces a checklist document; the actual secret values are added by a human in repo Settings.

**Files:**
- Create: `docs/release-secrets.md`

- [ ] **Step 1: Write the setup doc**

`docs/release-secrets.md`:

```markdown
# Release secrets (GitHub → Settings → Secrets and variables → Actions)

| Secret | What | How to get it |
|--------|------|---------------|
| `DEVELOPER_ID_CERT_P12_BASE64` | Developer ID Application cert + private key, exported as .p12, base64'd | Keychain Access → export the "Developer ID Application: …" identity as .p12, then `base64 -i cert.p12 | pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | Password set when exporting the .p12 | You choose it at export time |
| `KEYCHAIN_PASSWORD` | Any random string; used to create a temp keychain in CI | `openssl rand -base64 24` |
| `NOTARY_APPLE_ID` | Apple ID email for notarization | Your developer account email |
| `NOTARY_TEAM_ID` | 10-char Team ID | Apple Developer → Membership |
| `NOTARY_APP_PASSWORD` | App-specific password for notarytool | appleid.apple.com → App-Specific Passwords |
| `DEVELOPER_ID_IDENTITY` | Full identity name, e.g. `Developer ID Application: Your Name (TEAMID)` | `security find-identity -v -p codesigning` |

After adding all secrets, Task 3's workflow can run on a tag push.
```

- [ ] **Step 2: Verify**

Confirm each secret name in `release.yml` (Task 3) has a matching row here. No automated check — eyeball it.

- [ ] **Step 3: Commit**

```bash
git add docs/release-secrets.md
git commit -m "docs: document release signing/notarization secrets"
```

---

### Task 3: Release workflow (sign + notarize + staple + DMG + publish)

This runs on a `v*` tag. It is wired and parameterized now; the `Build .app` step is the integration seam that activates once the menubar app target exists. Until then, the workflow validates structurally on push of the file but its build step is a placeholder pointer to the app-target plan (NOT a hidden TODO — an explicit dependency).

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the workflow**

`.github/workflows/release.yml`:

```yaml
name: Release
on:
  push:
    tags: ["v*"]

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Import Developer ID certificate
        env:
          CERT_B64: ${{ secrets.DEVELOPER_ID_CERT_P12_BASE64 }}
          CERT_PW: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
          KC_PW: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          echo "$CERT_B64" | base64 --decode > cert.p12
          security create-keychain -p "$KC_PW" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$KC_PW" build.keychain
          security import cert.p12 -k build.keychain -P "$CERT_PW" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PW" build.keychain
          rm cert.p12

      - name: Build .app
        run: |
          # DEPENDENCY: the menubar app target (separate plan) produces AutoTrigger.app.
          # Once it exists, replace this with the real build, e.g.:
          #   xcodebuild -scheme AutoTrigger -configuration Release \
          #     -derivedDataPath build CODE_SIGNING_ALLOWED=NO
          # and set APP_PATH to the built bundle.
          echo "::error::Build .app step requires the menubar app target (see app-target plan)"
          exit 1

      - name: Codesign (Developer ID, hardened runtime)
        env:
          IDENTITY: ${{ secrets.DEVELOPER_ID_IDENTITY }}
        run: |
          codesign --force --deep --options runtime --timestamp \
            --sign "$IDENTITY" "build/AutoTrigger.app"
          codesign --verify --strict --verbose=2 "build/AutoTrigger.app"

      - name: Package DMG
        run: |
          hdiutil create -volname AutoTrigger -srcfolder "build/AutoTrigger.app" \
            -ov -format UDZO "AutoTrigger.dmg"

      - name: Notarize + staple
        env:
          APPLE_ID: ${{ secrets.NOTARY_APPLE_ID }}
          TEAM_ID: ${{ secrets.NOTARY_TEAM_ID }}
          APP_PW: ${{ secrets.NOTARY_APP_PASSWORD }}
        run: |
          xcrun notarytool submit "AutoTrigger.dmg" \
            --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PW" --wait
          xcrun stapler staple "AutoTrigger.dmg"
          xcrun stapler validate "AutoTrigger.dmg"

      - name: Publish GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: AutoTrigger.dmg
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Verify**

- Structural: push the file; GitHub parses it (no syntax error shown in the Actions tab).
- Functional (after the app target exists): replace the `Build .app` step per its comment, push a tag `v0.1.0`, and confirm: the job goes green, the Release has `AutoTrigger.dmg` attached, and `xcrun stapler validate AutoTrigger.dmg` passes locally on the downloaded artifact. Also `spctl -a -t open --context context:primary-signature -v AutoTrigger.dmg` should say `accepted`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add Developer ID sign + notarize + staple + DMG release workflow"
```

---

## Out of scope for this plan

- The menubar **app target** itself (the thing being signed) — separate plan. This workflow's `Build .app` step is the explicit seam where that plugs in.
- Auto-update / Sparkle feed — v1 ships manual download from GitHub Releases.
- Version bumping automation — tag-driven; the tag IS the version.

## Self-Review

- **Spec coverage:** T6 = "CI: Developer ID 签名 + 公证 + GitHub Release" → Task 1 (CI test, runs now), Task 2 (secrets), Task 3 (sign + notarize + staple + DMG + publish). Matches design doc's distribution decision (Developer ID + notarization, not App Store).
- **Placeholder scan:** the `Build .app` step's `exit 1` + `::error::` is an *intentional explicit dependency marker* on the app-target plan, not a silent TODO — it fails loudly with a pointer so no one ships a broken release thinking it works. Every other step is complete and runnable.
- **Type/name consistency:** secret names in `release.yml` (`DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_APP_PASSWORD`, `DEVELOPER_ID_IDENTITY`) all match the rows in `docs/release-secrets.md`. App/DMG names (`AutoTrigger.app`, `AutoTrigger.dmg`) consistent across steps.
