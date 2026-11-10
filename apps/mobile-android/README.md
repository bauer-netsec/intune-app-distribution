# Android – app-beskyttelse og appdistribusjon (Intune)

Bakgrunn og anbefalinger: [docs/mobilklargjoring-android.md](../../docs/mobilklargjoring-android.md) og [oversikten](../../docs/mobilklargjoring-oversikt.md).

| Script | Gjør |
| --- | --- |
| [`New-IntuneAndroidAppProtectionPolicy.ps1`](New-IntuneAndroidAppProtectionPolicy.ps1) | Oppretter en Android-app-beskyttelsespolicy: nivå 2 + PIN fra nivå 3, blokkert skjermbilde, Play Integrity, Verify Apps og krav om enhetslås. Velger målapper, lager eller gjenbruker filter og tildeler en brukergruppe. |
| [`New-IntuneAndroidManagedPlayOrLobApp.ps1`](New-IntuneAndroidManagedPlayOrLobApp.ps1) | Sjekker Managed Google Play-koblingen. Finner en Play-app på pakkenavn, eller godkjenner og synkroniserer den med `-ApproveAndSync`. Tildeler appen, eller en eksisterende app (`-AppId`, for eksempel LOB `.apk`). |

## Forutsetninger

Disse kan ikke scriptes. Scriptene sjekker dem og stopper med forklaring:

1. **Intune koblet til Managed Google Play** (Devices > Enrollment > Android > Prerequisites > Managed Google Play). Scriptet krever `bindStatus` `bound` eller `boundAndValidated`; ellers stopper det. Uten koblingen kan ingen Play-apper legges til.
2. Private apper (`.apk`/`.aab`) og nettapper lages i Managed Google Play-vinduet i admin-senteret. Synk, og tildel deretter med `-PackageId` eller `-AppId`.
3. **Company Portal** må være installert på enheten for at APP skal virke, også uten enrollment.
4. Registreringsbegrensninger: tillat work profile, blokker device administrator.
5. PowerShell 5.1 eller 7 og `Microsoft.Graph.Authentication`.
6. Intune-rolle (for eksempel *Application Manager*), eller app-registrering med programtillatelser.

## Pålogging

Som for iOS:
- interaktiv `Connect-MgGraph`, eller
- app-only med **alle tre** `-TenantId`, `-ClientId` og `-CertificateThumbprint`.

Aldri klienthemmelighet. Scopes står i `.NOTES`.

## Eksempler

```powershell
# APP uten enrollment for pilotgruppen
.\New-IntuneAndroidAppProtectionPolicy.ps1 -UserGroupName 'Pilot - Mobil APP - Brukere' -WhatIf
.\New-IntuneAndroidAppProtectionPolicy.ps1 -UserGroupName 'Pilot - Mobil APP - Brukere'

# Registrerte enheter (work profile/fully managed), med patchnivå
.\New-IntuneAndroidAppProtectionPolicy.ps1 -DeviceManagementScope Managed -UserGroupName 'Pilot - Mobil APP - Brukere' -MinimumRequiredPatchVersion '2026-08-01'

# Enklere Play Integrity-evaluering hvis eldre enheter ikke klarer maskinvarebasert
.\New-IntuneAndroidAppProtectionPolicy.ps1 -UserGroupName 'Pilot - Mobil APP - Brukere' -PlayIntegrityEvaluationType basic

# Slack fra Managed Google Play (allerede godkjent og synket) som Available
.\New-IntuneAndroidManagedPlayOrLobApp.ps1 -PackageId com.Slack -GroupName 'Pilot - Slack Android - Brukere' -Intent Available

# Godkjenn, synk og vent (maks 10 min), deretter Required
.\New-IntuneAndroidManagedPlayOrLobApp.ps1 -PackageId com.Slack -ApproveAndSync -ApproveAllPermissions -GroupName 'Pilot - Slack Android - Brukere' -Intent Required

# Tildel en eksisterende LOB-app (bare fully managed/dedikerte enheter)
.\New-IntuneAndroidManagedPlayOrLobApp.ps1 -AppId '<app-id>' -GroupId '<gruppe-id>' -Intent Required
```

## Oppførsel

- **Idempotent** som iOS-scriptene, og tildelinger flettes.
- `-ApproveAndSync` krever `-ApproveAllPermissions`. Appens tillatelser godkjennes på vegne av organisasjonen; vurder dette bevisst.
- Scriptet advarer om `androidLobApp` (virker bare på fully managed og dedikerte enheter) og `androidStoreApp` (ikke Android Enterprise).
- **Graph:**
  - Beta for `mobileApps` og tildelinger, fordi `androidManagedStoreApp` bare er dokumentert i beta.
  - Beta for Managed Google Play-koblingen og for `approveApps`/`syncApps`.
  - Beta for app-beskyttelse og filtre.

## Usikkerhet

- Microsofts hovedvei for godkjenning er admin-senteret. `approveApps` er dokumentert i Graph beta, men har lite veiledning.
- Synk kan ta lengre tid enn `-SyncTimeoutMinutes`. Kjør da scriptet på nytt uten `-ApproveAndSync`.
- Samsung Knox-attestasjon er ikke satt, fordi den gjelder alle målrettede enheter.
- Graph-feltene for Play Integrity heter fortsatt `...SafetyNet...`.
- Beta-API-er kan endres. Standard Android 12.0 må vurderes mot egen enhetspark.
