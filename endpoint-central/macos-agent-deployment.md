# ManageEngine Endpoint Central — macOS Agent Deployment via Intune

## Objective
Deploy the ManageEngine Endpoint Central macOS agent (UEM agent package) to a test macOS device through Microsoft Intune, following ManageEngine's vendor-documented deployment method rather than a generic PKG upload, after an initial generic attempt failed.

## Environment
- Intune tenant (production), test macOS device (Apple Silicon, macOS Mojave 10.14+ minimum)
- ManageEngine Endpoint Central macOS agent package (`UEMS_MacAgent.pkg`)
- ManageEngine-provided server connection config (`.plist`, contains server address and auth key — **not included in this repo**, environment-specific and sensitive)

## Incident 1: App Upload Fails — "The file provided is not supported."

### Symptom
Uploading `UEMS_MacAgent.pkg` as an Intune **macOS app (PKG)** type failed outright with:

> The file provided is not supported.

### Ruled Out
- Chip architecture mismatch (Intel vs. Apple Silicon) — initial guess, incorrect; confirmed device chip and package were compatible.
- Code signing issue — package is vendor-signed and valid.

### Root Cause
ManageEngine's own Intune deployment documentation specifies a non-generic method: the agent **must** be packaged as an Intune **Line-of-business (LOB) app**, not a generic **macOS app (PKG)** type. The PKG-type path doesn't handle this package correctly and fails at upload.

### Fix
Rebuilt the app as:
- **App type:** Line-of-business app
- **Package:** `UEMS_MacAgent.pkg`
- **Ignore app version:** Yes
- **Install as managed:** No
- **Minimum OS:** macOS Mojave 10.14

## Incident 2: App Installs Fail — "The app state is unknown (0x87D13B67)"

### Symptom
After fixing the upload (Incident 1), device-side install status showed **Failed** with the generic code `0x87D13B67` ("The app state is unknown").

### Root Cause
The LOB app wizard auto-populates **all** bundle IDs found in the PKG's component receipt as detection rules — in this case ~15 separate bundle IDs (helper tools, uninstallers, notifiers, a malformed `$(PRODUCT_BUNDLE_IDENTIFIER)` placeholder, etc.), none of which is the correct single detection target. ManageEngine's documentation specifies the package should be detected by **one** bundle ID only:

```
com.manageengine.dcagenttrayicon
```

Leaving the full auto-populated list in place caused detection logic to fail, which Intune reported as the generic "app state unknown" error.

### Fix
In the LOB app's **Included apps** (detection rules), deleted every entry except:

| Bundle ID | Version |
|---|---|
| `com.manageengine.dcagenttrayicon` | `11.5.2627.50.M` |

Assignment: Required, scoped to the isolated test device group.

## Incident 3: Companion Configuration Profile Fails Validation — Error `-2016341103` / `0x87d11391`

### Symptom
A macOS **Preference file** Configuration Profile (domain `com.manageengine.ems`), used to push the agent's server-connection config ahead of app install, failed device check-in with:

> We couldn't validate your file. Check for formatting errors and try again.

### Root Cause (self-inflicted, documented for the record)
ManageEngine's instructions describe trimming the vendor-provided `.plist` down to just its configuration content. Taken too literally, the file's required outer structure was stripped along with it — the `<?xml version="1.0"?>` declaration, `<!DOCTYPE plist ...>`, and the outer `<plist version="1.0">...</plist>` wrapper — leaving a bare `<dict>...</dict>` fragment. A `.plist` with no XML declaration/DOCTYPE/plist wrapper is not a valid property list, and Intune's macOS preference-file validator rejects it with error `-2016341103`.

### Fix
Rebuilt the file preserving the full, valid plist structure around the same configuration keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- vendor-provided configuration keys (server host, auth key, cert) -->
    <!-- redacted / environment-specific — not reproduced here -->
</dict>
</plist>
```

Re-uploaded as the replacement file on the existing Configuration Profile (Intune's Preference file field requires replacing the file wholesale — it has no inline edit).

### Verification
- Configuration Profile device status: `Succeeded: 1`.
- Rebuilt LOB app assigned and pending device check-in at time of writing.

## Lessons Learned
- Vendor "generic Intune app deployment" instructions do not always apply — check for a vendor-specific deployment doc before assuming the standard PKG/LOB path. ManageEngine documents the LOB-app-plus-single-bundle-ID pattern explicitly; the generic path fails silently with an unhelpful upload error.
- Intune's auto-populated detection rule list from a PKG receipt is a starting point, not a correct default — trim to exactly what the vendor specifies.
- A `.plist` is only valid with its full XML declaration, DOCTYPE, and `<plist>` wrapper intact. "Strip the file down to the config" means trim the *keys*, never the structural wrapper. Error `-2016341103` / `0x87d11391` on a macOS preference file is the specific signature of this mistake.
- Intune's Property List file upload field is a file-replace operation, not an inline text editor — there is no in-console edit, only re-upload.

## Status
Both incidents resolved at the configuration/deployment level. Final device check-in confirming successful agent install (post-fix) pending at time of writing.
