# Releasing Highlight Bar (macOS) — signing, notarization, updates

The release workflow ([.github/workflows/macos-release.yml](.github/workflows/macos-release.yml))
runs on a version tag (`v*`) and:

1. builds the app and embeds **Sparkle.framework** (Hardened Runtime),
2. signs it with your **Developer ID Application** identity,
3. **notarizes** with `notarytool` and **staples** the ticket,
4. publishes `HighlightBar-macos.zip`, and
5. emits the **Sparkle EdDSA signature** for your appcast.

Everything in the code/CI is scaffolded. To produce a real signed build you must
add the items below. **You generate and enter all of these yourself** — they are
your credentials; this repo and the assistant never create or hold them.

> Until these are set, a tag build falls back to an ad-hoc signature and the
> notarization step fails. That is expected.

## 1. Add GitHub **secrets**
Repo → Settings → Secrets and variables → Actions → **Secrets**:

| Secret | What it is | How to get it |
| --- | --- | --- |
| `MACOS_CERT_P12_BASE64` | Developer ID Application cert + key, base64 of a `.p12` | Export the identity from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | password you set on that `.p12` | you choose it at export time |
| `MACOS_SIGN_IDENTITY` | the identity string | `security find-identity -v -p codesigning` → e.g. `Developer ID Application: Your Name (TEAMID)` |
| `AC_API_KEY_ID` | App Store Connect API **Key ID** | App Store Connect → Users and Access → Integrations → App Store Connect API → generate a key (Developer role) |
| `AC_API_ISSUER_ID` | the **Issuer ID** on that same page | same page |
| `AC_API_KEY_P8` | contents of the downloaded `AuthKey_XXXX.p8` | downloaded once when you create the key; paste the whole file |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA **private** key | see step 3 |

## 2. Add GitHub **variables**
Same page → **Variables** (these are not secret):

| Variable | Example | Notes |
| --- | --- | --- |
| `BUNDLE_ID` | `com.yourname.highlightbar` | replaces the local `com.local.highlightbar`; should be a reverse-DNS id tied to your Team |
| `SU_FEED_URL` | `https://yourname.github.io/Highlighter/appcast.xml` | where you host the appcast (GitHub Pages or a Releases asset URL) |
| `SU_PUBLIC_ED_KEY` | `abc123…==` | the Sparkle **public** key from step 3 (also baked into Info.plist) |

## 3. Generate the Sparkle EdDSA key pair
Use the tool that ships with the resolved Sparkle package:

```bash
cd HighlightBar
swift package resolve
BIN="$(find .build -path '*/bin/generate_keys' -type f | head -n1)"

# Creates a key pair (private key stored in your login Keychain) and prints
# the PUBLIC key — put that in the SU_PUBLIC_ED_KEY variable:
"$BIN"

# Export the PRIVATE key to a file for the SPARKLE_ED_PRIVATE_KEY secret:
"$BIN" -x sparkle_private_key.txt   # paste this file's contents into the secret, then delete it
```

Apple Team ID, the Developer ID Application certificate, and the App Store
Connect API key all come from your Apple Developer account — create/download
them there. (An app-specific password + Apple ID can substitute for the API key;
if you prefer that, tell me and I'll switch the notarize step to
`--apple-id/--password/--team-id`.)

## 4. Cut a release
```bash
git tag v0.2.0
git push origin v0.2.0
```
The workflow signs, notarizes, staples, and uploads `HighlightBar-macos.zip` plus
`sparkle-signature.txt` to the GitHub release.

## 5. Update the appcast
Add an `<item>` to your `appcast.xml` (hosted at `SU_FEED_URL`) using the
`sparkle:edSignature` and `length` from `sparkle-signature.txt`, the release
version, and the `.zip` download URL. See Sparkle's `SampleAppcast.xml` (in the
resolved package) for the format.

## Notes
- **Do not enable the App Sandbox** — it would block the overlays and global
  hotkeys. The Hardened Runtime is enabled at signing time
  ([HighlightBar.entitlements](HighlightBar/HighlightBar.entitlements) keeps the
  app un-sandboxed).
- If notarization ever reports a **library-validation** failure, add
  `com.apple.security.cs.disable-library-validation` to the entitlements. With a
  single Developer ID signing the app and the embedded Sparkle.framework, it
  should not be needed.
