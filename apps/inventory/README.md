# Forutsetningsrapport før utrulling (Intune)

[`Get-IntunePreDeploymentReport.ps1`](Get-IntunePreDeploymentReport.ps1) **leser** tenanten og skriver en Markdown-rapport. Den endrer ingenting i Intune.

## Innhold

| Avsnitt | Viser |
| --- | --- |
| 0. Funn | Det som bør fikses før utrulling. For eksempel:<br>• APNs-, ADE- eller VPP-token som utløper eller er utløpt<br>• Managed Google Play ikke koblet<br>• Device administrator tillatt<br>• Utløpte Android-tokens<br>• Apper og policyer uten tildeling |
| 1. Apper | Navn, plattform/type, versjon og publiseringsstatus. Tildelinger med intent (Required/Available/Uninstall), mål (gruppe, alle brukere/enheter, utelatelse) og filter. |
| 2. Gruppeindeks | Omvendt oppslag: gruppe → apper med intent |
| 3. Samsvar | Policyer per plattform, tildelinger, status fra `deviceStatusOverview`, og ikke-samsvarende enheter (maks `-MaxDevicesPerPolicy`). **Ingen tall er beregnet eller gjettet; alt kommer fra Graph.** |
| 4a. iOS/iPadOS | APNs, ADE-token og -profiler, brukerinitierte profiler (brukerregistrering), VPP-token og registreringsbegrensninger |
| 4b. Android | Managed Google Play-kobling, Android Enterprise-profiler (fully managed/dedikert/COPE), work profile- og device admin-begrensninger |
| 5a/5b. App-beskyttelse | iOS og Android separat, med kolonnen **med/uten enrollment** (filter og `targetedAppManagementLevels`) |
| 6. Enheter | Antall administrerte enheter per OS og samsvarsstatus (kan slås av) |

Hvert avsnitt hentes for seg. Mangler en rettighet eller feiler et kall, skrives feilen i det avsnittet, og resten av rapporten lages likevel. Hemmeligheter (registreringstokens, QR-koder, Wi-Fi-passord, VPP-token) hentes aldri; scriptet bruker `$select`.

## Kjøring

```powershell
# Interaktiv; rapporten lagres i gjeldende mappe med tidsstempel (Europe/Oslo)
.\Get-IntunePreDeploymentReport.ps1

# Egen sti, uten enhetsdetaljer
.\Get-IntunePreDeploymentReport.ps1 -OutputPath .\rapporter\for-pilot.md -IncludeComplianceDeviceDetails:$false

# App-only med sertifikat (alle tre må oppgis; aldri klienthemmelighet)
.\Get-IntunePreDeploymentReport.ps1 -TenantId '<tenant-id>' -ClientId '<klient-id>' -CertificateThumbprint '<tommelavtrykk>'
```

Rettigheter (bare lesing):
- `DeviceManagementApps.Read.All`
- `DeviceManagementConfiguration.Read.All`
- `DeviceManagementServiceConfig.Read.All`
- `DeviceManagementManagedDevices.Read.All` (avsnitt 6)
- `Group.Read.All`

Delegert pålogging krever i tillegg en Intune-rolle med lesetilgang, for eksempel *Read Only Operator*.

## Slik brukes rapporten

1. **Før pilot:** kjør rapporten og rydd i *Funn*. Forny tokens i god tid, koble Managed Google Play og blokker device administrator.
2. **Sjekk konflikter** i gruppeindeksen: får pilotgruppen allerede samme app med annen intent, eller både gammel MSI og ny MSIX (Windows)?
3. **Sjekk APP-dekning:**
   - Har både iOS og Android en policy for uadministrerte enheter (MAM-WE)?
   - Har registrerte enheter en egen policy, eller den samme?
4. **Etter utrulling:** kjør på nytt og sammenlign filene (`git diff` eller `Compare-Object`). Lagre rapportene sammen med endringsloggen.

## Kjente begrensninger

- Samsvarspolicyer laget i Settings catalog vises ikke; de ligger ikke i `deviceCompliancePolicies`.
- ADE-profiler laget i den nye opplevelsen «Enrollment policies» vises kanskje ikke under `enrollmentProfiles`. Kontroller i admin-senteret.
- Enkelte felt vises rått fra Graph, for eksempel `isMandatory` og `enableAuthenticationViaCompanyPortal` på ADE-profiler.
- Beta-ressurser kan endres. Scriptet tåler manglende felt og skriver «–».
