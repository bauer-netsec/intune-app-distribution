# iPhone/iOS – app-beskyttelse og appdistribusjon (Intune)

Bakgrunn og anbefalinger: [docs/mobilklargjoring-ios.md](../../docs/mobilklargjoring-ios.md) og [oversikten](../../docs/mobilklargjoring-oversikt.md).

| Script | Gjør |
| --- | --- |
| [`New-IntuneIosAppProtectionPolicy.ps1`](New-IntuneIosAppProtectionPolicy.ps1) | Oppretter en iOS/iPadOS-app-beskyttelsespolicy (nivå 2 + PIN fra nivå 3), velger målapper, lager eller gjenbruker filter for uadministrerte enheter, og tildeler en brukergruppe |
| [`New-IntuneIosStoreOrLobApp.ps1`](New-IntuneIosStoreOrLobApp.ps1) | Legger til en App Store-app (oppslag i Apples søke-API), finner eller synkroniserer en VPP-app, lager et webklipp, eller tildeler en eksisterende app (for eksempel LOB `.ipa`). Sjekker APNs og VPP-token først. |

## Forutsetninger

Disse kan ikke scriptes. Scriptene sjekker dem og stopper med forklaring:

1. **Apple MDM Push-sertifikat** gyldig. Stopper hvis det mangler eller er utløpt, og advarer under 30 dager.
2. **Apple Business** med ADE-token for firmaeide enheter, og **VPP-token** for `-VppBundleId` (appen må være kjøpt/tildelt i Apple Business).
3. LOB `.ipa` lastes opp i admin-senteret (Apps > All Apps > Create > iOS/iPadOS > Line-of-business app) og tildeles deretter med `-AppId`.
4. Registrerte enheter: app-konfigurasjon med `IntuneMAMUPN`/`IntuneMAMOID` (+ `IntuneMAMDeviceID` for tredjeparts- og LOB-apper). Uten den gjelder policyen for «Administrerte enheter» ikke.
5. PowerShell 5.1 eller 7 og modulen `Microsoft.Graph.Authentication`:
   `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`
6. Intune-rolle som kan opprette policyer og apper (for eksempel *Application Manager*), eller app-registrering med programtillatelser.

## Pålogging

- **Interaktiv** (standard): `Connect-MgGraph` med minste nødvendige scopes. Scopes står i `.NOTES` i hvert script.
- **App-only med sertifikat:** oppgi *alle tre* `-TenantId`, `-ClientId` og `-CertificateThumbprint` (sertifikatet i brukerens eller maskinens sertifikatlager). Delvis utfylt gir feil.
- **Aldri** klienthemmelighet.

## Eksempler

Prøv alltid først med `-WhatIf`.

```powershell
# APP uten enrollment (MAM-WE) for pilotgruppen, alle Microsoft-apper
.\New-IntuneIosAppProtectionPolicy.ps1 -UserGroupName 'Pilot - Mobil APP - Brukere' -WhatIf
.\New-IntuneIosAppProtectionPolicy.ps1 -UserGroupName 'Pilot - Mobil APP - Brukere'

# Egen policy for registrerte enheter (filteret brukes som Exclude)
.\New-IntuneIosAppProtectionPolicy.ps1 -DeviceManagementScope Managed -UserGroupName 'Pilot - Mobil APP - Brukere'

# Bare utvalgte apper (bundle-ID-er)
.\New-IntuneIosAppProtectionPolicy.ps1 -AppGroupType selectedPublicApps -BundleIds 'com.microsoft.Office.Outlook','com.microsoft.skype.teams' -SkipAssignment

# Slack fra App Store (id 618783545) som Available til brukergruppe
.\New-IntuneIosStoreOrLobApp.ps1 -AppStoreId 618783545 -GroupName 'Pilot - Slack iOS - Brukere' -Intent Available

# VPP-app med enhetslisens som Required (synk tokenet hvis appen ikke finnes ennå)
.\New-IntuneIosStoreOrLobApp.ps1 -VppBundleId 'com.tinyspeck.chatlyio' -SyncVppToken -UseDeviceLicensing -GroupName 'Pilot - Slack iOS - Enheter' -Intent Required

# Webklipp åpnet i Edge
.\New-IntuneIosStoreOrLobApp.ps1 -WebClipUrl 'https://intranett.example.no' -DisplayName 'Intranett' -UseManagedBrowser -GroupName 'Pilot - Mobil APP - Brukere'

# App-only
.\New-IntuneIosStoreOrLobApp.ps1 -AppId '<app-id>' -GroupId '<gruppe-id>' -TenantId '<tenant-id>' -ClientId '<klient-id>' -CertificateThumbprint '<tommelavtrykk>'
```

## Oppførsel

- **Idempotent:**
  - En policy med samme visningsnavn opprettes ikke på nytt.
  - Et eksisterende filter valideres mot plattform og regel.
  - En gruppe som allerede er tildelt hoppes over.
- **Tildelinger flettes:** APP-`/assign` erstatter alle tildelinger, så scriptet sender eksisterende tildelinger sammen med de nye. For apper legges én tildeling til med `POST /assignments`.
- **Graph:** `Invoke-MgGraphRequest` mot v1.0 og beta. Beta brukes for app-beskyttelsesfelt og filtre, og for `iosStoreApp`, fordi v1.0 bare har minimum-iOS opp til 15.

## Usikkerhet

- At `targetApps` godtar tom `apps`-liste sammen med `appGroupType = allMicrosoftApps` er ikke eksplisitt dokumentert. Kontroller *Apps* på policyen i admin-senteret etter første kjøring.
- Beta-API-er kan endres uten varsel.
- Standard OS-versjoner (18.0 påkrevd, advarsel under 26.0) må vurderes mot egen enhetspark før produksjon.
