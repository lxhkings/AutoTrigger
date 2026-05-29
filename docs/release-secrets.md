# Release secrets (GitHub → Settings → Secrets and variables → Actions)

| Secret | What | How to get it |
|--------|------|---------------|
| `DEVELOPER_ID_CERT_P12_BASE64` | Developer ID Application cert + private key, exported as .p12, base64'd | Keychain Access → export the "Developer ID Application: …" identity as .p12, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | Password set when exporting the .p12 | You choose it at export time |
| `KEYCHAIN_PASSWORD` | Any random string; used to create a temp keychain in CI | `openssl rand -base64 24` |
| `NOTARY_APPLE_ID` | Apple ID email for notarization | Your developer account email |
| `NOTARY_TEAM_ID` | 10-char Team ID | Apple Developer → Membership |
| `NOTARY_APP_PASSWORD` | App-specific password for notarytool | appleid.apple.com → App-Specific Passwords |
| `DEVELOPER_ID_IDENTITY` | Full identity name, e.g. `Developer ID Application: Your Name (TEAMID)` | `security find-identity -v -p codesigning` |

After adding all secrets, Task 3's workflow can run on a tag push.
