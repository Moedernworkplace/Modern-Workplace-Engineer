# macOS Automated Device Enrollment (ADE) — Legacy Profile → Enrollment Policy Migration

## Objective
Migrate macOS device enrollment from the deprecated legacy Apple "Profiles" framework in Intune to the modern "Enrollment Policies" framework (ADE-based), validated end-to-end on an isolated test device before touching the single live production device still on the legacy profile.

## Environment
- Intune tenant (production)
- Apple Business Manager (ABM) — Automated Device Enrollment token
- Test device: enrolled via ABM, assigned to a dedicated test security group (not the production device group)
- Entra ID / Microsoft Graph PowerShell (`Microsoft.Graph` module)

## Background
Two non-interoperable enrollment systems exist side-by-side in the same Intune console:

- **Profiles** (legacy) — the original Apple enrollment program integration. One live production device still on this profile; ~9 stale/ghost device records with no corresponding physical hardware.
- **Enrollment Policies** (modern) — current ADE-based framework, required going forward. Devices only receive ADE policies if they're present in ABM; an Intune-only device record (never pushed through ABM) cannot be targeted by an Enrollment Policy regardless of group assignment.

Migration plan: stand up a new Enrollment Policy, validate fully on a throwaway test device via wipe + re-enrollment, confirm no impact to the live production device still bound to the legacy profile, then plan the production cutover separately.

## Incident: Apple Enrollment Policy "Device Group" Save Failure

### Symptom
Saving an Entra security group to the **Device Group** field of a new macOS Enrollment Policy repeatedly failed with:

> Unable to save device group for [group]. You cannot update this configuration because we could not find the security group you selected or the Intune Provisioning Client application is not an owner.

### Ruled Out
- Admin account permissions — tested with two separate admin accounts, same failure.
- Group corruption — tested with two different security groups, same failure.
- ABM token expiration — token confirmed `Active` in Intune.

### Root Cause
Apple Enrollment Policies require a specific **Intune service principal** to be an **owner** of the target Entra security group before that group can be saved as the policy's device group target. Microsoft's own documentation names this principal **"Intune Provisioning Client"** — but service principal display names are tenant-specific. In this tenant the same app registered under a different display name: **"Intune Autopilot ConfidentialClient"**.

Matching on display name alone led nowhere. The fix is to match on the fixed **AppID**, which is constant across tenants:

```
f1346770-5b25-470b-88bd-d5744ab7952c
```

That service principal was simply never added as an owner of the group — hence the save failure on every attempt, independent of which account or which group was used.

### Fix

```powershell
Connect-MgGraph -Scopes "Group.ReadWrite.All","Application.Read.All"

# Resolve the Intune enrollment service principal by fixed AppID (not display name)
$sp = Get-MgServicePrincipal -Filter "appId eq 'f1346770-5b25-470b-88bd-d5744ab7952c'"
# -> DisplayName: Intune Autopilot ConfidentialClient

# Resolve the target security group — match by exact Object ID if a
# displayName filter returns an empty/ambiguous result
$group = Get-MgGroup -Filter "startswith(displayName,'<group-name-prefix>')"

# Add the service principal as a group owner
$body = @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/" + $sp.Id
}
New-MgGroupOwnerByRef -GroupId $group.Id -BodyParameter $body

# Verify
Get-MgGroupOwner -GroupId $group.Id
```

After this, the Enrollment Policy's Device Group field saved cleanly and persisted on reload (Include / target group confirmed).

### Verification
- Re-opened the Enrollment Policy → Device Group tab → group shown as `Include`, saved without error.
- Confirmed via `Get-MgGroupOwner` that the service principal object ID appears in the group's owner list.

## Lessons Learned
- When Microsoft documentation names a specific service principal by **display name**, treat that as unreliable across tenants — resolve by **AppID** instead. This generalizes to any similar "system app must own/have access to X" requirement (Autopilot device preparation has the identical pattern).
- Rule out the trivial causes (permissions, token state, object corruption) fast and explicitly, then go straight to the thing the error message is actually describing literally — "application is not an owner" was the literal, correct description of the root cause the whole time.
- Test device groups should be dedicated and isolated from production device groups from the start, so troubleshooting changes can't accidentally touch a live device.

## Status
Device Group save confirmed fixed on the test Enrollment Policy. Production device group rollout (migrating the live device off the legacy "Profiles" framework) is planned as a separate, later-phase change — not yet executed.
