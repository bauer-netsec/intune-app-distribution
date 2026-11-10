# Appdistribusjon og klargjøring i Microsoft Intune

Script og dokumentasjon for appdistribusjon og klargjøring av Windows, iPhone/iOS og Android i Intune. Sjekket mot Microsoft Learn 10. november 2026 (Europe/Oslo).

## Innhold

| Område | Hva | Lenke |
| --- | --- | --- |
| **Slack for Windows** | Offisiell MSIX som LOB-app, enhetskontekst, Required til enhetsgruppe. Rydding av gammel MSI. | [apps/slack-windows/README.md](apps/slack-windows/README.md) |
| **Entra-pilotgruppe** | Oppretter pilotgruppe (`Pilot - <produkt> <teknologi> - <mål>`) | [apps/slack-windows/New-EntraSlackMsixPilotGroup.ps1](apps/slack-windows/New-EntraSlackMsixPilotGroup.ps1) |
| **Slack Enterprise-innstillinger** | Anbefalte innstillinger i Slack Enterprise | [apps/slack-windows/Slack-Enterprise-anbefalte-innstillinger.md](apps/slack-windows/Slack-Enterprise-anbefalte-innstillinger.md) |
| **Mobil – oversikt** | MAM/APP, MAM-WE, Company Portal, enrollment, distribusjon, forskjell fra Windows LOB | [docs/mobilklargjoring-oversikt.md](docs/mobilklargjoring-oversikt.md) |
| **iPhone/iOS** | Dokumentasjon: ADE/Apple Business, kontobasert brukerregistrering, VPP, App Store, LOB `.ipa`, webklipp, APP | [docs/mobilklargjoring-ios.md](docs/mobilklargjoring-ios.md) |
| | Script | [apps/mobile-ios/README.md](apps/mobile-ios/README.md) |
| **Android** | Dokumentasjon: work profile, fully managed, COPE, dedikert, Managed Google Play, LOB, APP | [docs/mobilklargjoring-android.md](docs/mobilklargjoring-android.md) |
| | Script | [apps/mobile-android/README.md](apps/mobile-android/README.md) |
| **Forutsetningsrapport** | Leser apper og tildelinger, grupper, samsvar, enrollment og APP før utrulling | [apps/inventory/README.md](apps/inventory/README.md) |

## Struktur

```text
intune-app-distribution/
├── README.md
├── docs/
│   ├── mobilklargjoring-oversikt.md
│   ├── mobilklargjoring-ios.md
│   └── mobilklargjoring-android.md
└── apps/
    ├── slack-windows/      Slack MSIX, MSI-rydding, pilotgruppe, Slack Enterprise
    ├── mobile-ios/         New-IntuneIosAppProtectionPolicy.ps1, New-IntuneIosStoreOrLobApp.ps1
    ├── mobile-android/     New-IntuneAndroidAppProtectionPolicy.ps1, New-IntuneAndroidManagedPlayOrLobApp.ps1
    └── inventory/          Get-IntunePreDeploymentReport.ps1
```

## Anbefalt rekkefølge

1. Kjør [forutsetningsrapporten](apps/inventory/README.md) og rett *Funn*.
2. Lag pilotgrupper:
   - Windows: enhetsgruppe for Slack MSIX
   - Mobil: brukergrupper for APP og apper
3. **Windows:** fjern gammel Slack-MSI, publiser Slack MSIX ([slack-windows](apps/slack-windows/README.md)).
4. **Mobil:** app-beskyttelse for iOS og Android, deretter apper ([iOS](apps/mobile-ios/README.md), [Android](apps/mobile-android/README.md)).
5. Kjør rapporten igjen, sammenlign, og utvid gruppene.

## Felles regler for scriptene

- PowerShell 5.1 eller 7, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`. Filene er UTF-8 med BOM.
- Microsoft Graph via `Microsoft.Graph.Authentication` (`Connect-MgGraph`, `Invoke-MgGraphRequest`), ikke den utgåtte `Microsoft.Graph.Intune`.
- Pålogging:
  - interaktiv, eller
  - app-only med sertifikat. Da må `-TenantId`, `-ClientId` og `-CertificateThumbprint` alle oppgis.
- **Aldri klienthemmelighet** i script. Ingen tenant-ID-er er hardkodet.
- Endringer støtter `-WhatIf` / `-Confirm`. Kjør alltid `-WhatIf` først.
- Minste nødvendige Graph-rettigheter står i `.NOTES` i hvert script.

## Forutsetninger som ikke kan scriptes

- **iOS:**
  - Apple MDM Push-sertifikat (årlig, samme Apple-konto)
  - Apple Business med ADE-token og VPP-token
  - Kjøp av apper i Apps and Books
  - Service discovery-fil for kontobasert brukerregistrering
  - Opplasting av LOB `.ipa`
  - App-konfigurasjon med `IntuneMAMUPN` for administrerte enheter
- **Android:**
  - Kobling til Managed Google Play
  - Opplasting av private apper og nettapper i Managed Google Play
  - Company Portal på enhetene (påkrevd for APP)
- **Alle:**
  - Intune-lisenser og RBAC-rolle
  - Conditional Access-policyer
  - App-registrering med sertifikat for app-only

Scriptene sjekker forutsetningene der Graph gjør det mulig, og stopper med en tydelig melding hvis noe mangler.
