# Slack for Windows i Microsoft Intune

Anbefalt og støttet metode (sjekket 10. november 2026, Europe/Oslo): last opp **offisiell Slack MSIX** som **LOB-app** i **enhetskontekst**, tildelt **Required** til en **enhetsgruppe**.

Slack trakk tilbake både per-bruker-MSI og maskin-MSI 15. september 2025. Ny utrulling skal ikke bruke MSI eller SlackSetup.exe (per-bruker-installasjon).

## Hvorfor denne metoden

| Metode | Bruk? | Begrunnelse |
| --- | --- | --- |
| LOB MSIX, enhetskontekst, Required, enhetsgruppe | Ja, førstevalg | Offisiell Slack-pakke, Intune provisionerer appen på enheten for nåværende og nye brukere |
| Win32-innpakning av `Add-AppxProvisionedPackage` | Bare unntak | Aktuelt hvis dere må tvinge MSI-rydding og MSIX i én pakke. Mer å vedlikeholde enn LOB |
| Microsoft Store-app | Nei, ikke førstevalg | Kan fungere, men dere styrer ikke pakken like presist som med offisiell MSIX i LOB |
| Utgått MSI eller SlackSetup.exe | Nei | MSI er pensjonert. EXE installerer per bruker og er vanskelig å styre i enterprise |

Viktig begrensning fra Microsoft: MSIX/APPX i **enhetskontekst** må tildeles en **enhetsgruppe**. Brukergruppe gir feil. **Available** kan ikke kombineres med enhetskontekst.

Hvis maskinene allerede har gammel Slack-MSI, må MSI avinstalleres først. MSIX kan ikke installeres oppå MSI.

## Script

- `New-IntuneSlackWindowsApp.ps1` — laster ned offisiell MSIX, publiserer den i Intune og tildeler den.
- `Uninstall-LegacySlackMsi.ps1` — fjerner gammel Slack-MSI. Kjør som Win32-app eller plattformscript i systemkontekst **før** MSIX-appen.

### Publisere Slack

Kjør fra en administrasjons-PC der du kan logge på tenant med rettighet til apper i Intune (`DeviceManagementApps.ReadWrite.All`). Slå opp gruppen med `Group.Read.All` hvis du bruker gruppenavn.

```powershell
# Interaktiv pålogging (vanlig ved manuell kjøring)
.\New-IntuneSlackWindowsApp.ps1 -DeviceGroupId '<entra-enhetsgruppe-guid>'

# Eller slå opp gruppen på visningsnavn
.\New-IntuneSlackWindowsApp.ps1 -DeviceGroupName 'Intune-Windows-Enheter'
```

For automatisering: app-registrering med **sertifikat**, ikke klienthemmelighet.

```powershell
.\New-IntuneSlackWindowsApp.ps1 `
  -TenantId '<tenant-id>' `
  -ClientId '<app-id>' `
  -CertificateThumbprint '<tommelavtrykk>' `
  -DeviceGroupId '<entra-enhetsgruppe-guid>'
```

### Fjerne gammel MSI først

```powershell
# Installasjonskommando i en Win32-app, systemkontekst, Required til samme enhetsgruppe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-LegacySlackMsi.ps1
```

## Kilder

- [Deploy Slack for Windows](https://slack.com/help/articles/212475728-Deploy-Slack-for-Windows)
- [Slack feature and plan retirements](https://slack.com/help/articles/4426294050451-Slack-feature-and-plan-retirements)
- [Windows-appdistribusjon i Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/deploy-windows)
- [Styring av skrivebordsapp (AutoUpdate)](https://slack.com/help/articles/11906214948755-Manage-desktop-app-configurations)

Full dokumentasjon skal ligge i Confluence når Atlassian er koblet til.

## Pilotgruppe i Entra ID

Fast gruppenavnkonvensjon, brukt likt i Entra, Intune, script og dokumentasjon:

`Pilot - <produkt> <teknologi> - <mål>`

For Slack er visningsnavnet **Pilot - Slack MSIX - Enheter** (kallenavn `Pilot-Slack-MSIX-Enheter`). Det er en tildelt sikkerhetsgruppe for enheter, fordi Intune krever enhetsgruppe når MSIX tildeles i enhetskontekst.

```powershell
.\New-EntraSlackMsixPilotGroup.ps1
```

Scriptet oppretter gruppen bare hvis den ikke allerede finnes, og skriver ut objekt-ID-en som brukes som `-DeviceGroupId` i `New-IntuneSlackWindowsApp.ps1`.
