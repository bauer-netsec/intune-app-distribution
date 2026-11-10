# iPhone/iOS (iPadOS) i Intune – klargjøring og appdistribusjon

Sjekket mot Microsoft Learn 10. november 2026 (Europe/Oslo). Gjelder iPhone og iPad. Android er beskrevet separat i [mobilklargjoring-android.md](mobilklargjoring-android.md).

## 1. Forutsetninger (kan ikke scriptes)

| Forutsetning | Hvor | Merknad |
| --- | --- | --- |
| **Apple MDM Push-sertifikat (APNs)** | Devices > Enrollment (Device onboarding) > Apple > Apple MDM Push certificate | Gjelder i 365 dager. Forny med **samme** Apple-konto. Etter utløp er det 30 dagers frist, ellers må enhetene registreres på nytt. |
| **Apple Business** (tidligere Apple Business Manager) | business.apple.com | Kjøp gjennom forhandler som kobler enhetene til Apple Business. Trengs for ADE og VPP. |
| **ADE-token** (.p7m) | Devices > Device onboarding > Enrollment > Apple mobile > Enrollment program tokens | Fornyes årlig |
| **VPP-/plasseringstoken** | Tenant administration > Connectors and tokens > Apple VPP tokens | Fornyes årlig. Last opp på nytt i **eksisterende** token, ikke lag nytt. Slå på *Automatic app updates*. |
| **Kontobasert brukerregistrering** | Webserver på e-postdomenet | Service discovery-fil `/.well-known/com.apple.remotemanagement` (JSON, uten filendelse), og Managed Apple-kontoer eller føderering mellom Apple Business og Entra ID |

Scriptene sjekker APNs og VPP-token og stopper med forklaring hvis de mangler. Forutsetningsrapporten viser også ADE-token og utløpsdatoer.

## 2. Enrollment-metoder

| Metode | Eierskap | Når | Merknad |
| --- | --- | --- | --- |
| **Automatisert enhetsregistrering (ADE)** | Firma | Nye eller tilbakestilte enheter kjøpt via Apple Business | Anbefalt med brukeraffinitet og **Setup Assistant med moderne autentisering + JIT-registrering**. Legacy Setup Assistant er fjernet (2610, oktober 2026). Sett en standard-policy før enhetene slås på. |
| ADE uten brukeraffinitet / Shared iPad | Firma | Kiosk, delte iPader | Ingen Company Portal-apper per bruker |
| **Kontobasert brukerregistrering** (Account Driven User Enrollment) | Privat | BYOD som skal ha jobbapper fra Intune | iOS/iPadOS 15+. Brukeren starter fra Innstillinger. Begrenset, personvernvennlig styring. Microsoft Authenticator som påkrevd app (JIT). |
| Enhetsregistrering med Company Portal / nettbasert enhetsregistrering | Privat eller firma | Når hele enheten skal styres uten ADE | Gir mer kontroll enn brukerregistrering |
| User enrollment with Company Portal | – | **Ikke for nye registreringer** | Bare for eksisterende enheter |
| **Bare APP (MAM-WE)** | Privat | BYOD uten enrollment | Ingen MDM; bare data i støttede apper beskyttes |

## 3. Intune Company Portal på iOS

- **ADE:** distribuer Company Portal **gjennom Intune som VPP-app** (kjøp den gratis i Apple Business), ikke fra App Store. App Store-versjonen er ikke kompatibel med ADE og får ikke automatiske oppdateringer.
- **Kontobasert brukerregistrering:** distribuer Company Portal-**nettappen** (webklipp til Company Portal-nettstedet).
- **Enhetsregistrering for BYOD:** brukeren henter Company Portal fra App Store og registrerer derfra.
- **MAM uten enrollment:** Company Portal trengs ikke. **Microsoft Authenticator** er megler-appen når Conditional Access krever app-beskyttelsespolicy.

## 4. Appdistribusjon på iOS

| Type | Graph-type | Når | Krav |
| --- | --- | --- | --- |
| **VPP-app** | `iosVppApp` | Firmaeide enheter, og lisensierte apper | Kjøpt i Apple Business (Apps and Books), synkronisert via token. **Enhetslisens** krever ingen Apple-konto. Opprettes ikke med Graph; synkroniseres inn. |
| App Store-app | `iosStoreApp` | Gratisapper der brukeren har egen Apple-konto | Opprettes med bundle-ID og App Store-URL |
| LOB-app (.ipa) | `iosLobApp` | Egne apper | Signert med provisjoneringsprofil. Intune varsler 30 dager før utløp. Last opp i admin-senteret: Apps > All Apps > Create > iOS/iPadOS > Line-of-business app. |
| Webklipp | `iosiPadOSWebClip` | Nettjenester, Company Portal-nettapp | Kan tvinges til Microsoft Edge |

Intent:
- **Required** krever enrollment. På overvåkede (supervised) ADE-enheter installeres appen stille; ellers får brukeren spørsmål.
- **Available** vises i Company Portal og tildeles **brukergrupper**.
- **Uninstall** fjerner appen.

## 5. App-beskyttelse (APP / MAM) på iOS

Opprettes under **Apps > Protection > Create policy > iOS/iPadOS**. Scriptet `New-IntuneIosAppProtectionPolicy.ps1` lager tilsvarende policy med Graph.

### Med og uten enrollment

- **Uten enrollment (MAM-WE):** tildel brukergruppen med filteret `(app.deviceManagementType -eq "Unmanaged")` som **Include**.
- **Bare registrerte enheter:** samme filter som **Exclude**.
- **Viktig på iOS:** en app regnes bare som administrert når den får app-konfigurasjonsnøklene **`IntuneMAMUPN` og `IntuneMAMOID`** via en app-konfigurasjonspolicy for administrerte enheter. Tredjeparts- og LOB-apper trenger i tillegg `IntuneMAMDeviceID`. Intune sender nøklene automatisk til noen Microsoft-apper (Outlook, Teams, Word, Excel, PowerPoint). Uten nøklene behandles enheten som uadministrert.

### Anbefalte innstillinger (scriptets standard)

Grunnlag: Microsofts nivå 2 «Enterprise enhanced». Avvik er markert.

| Område | Innstilling | Verdi | Graph-felt |
| --- | --- | --- | --- |
| Dataoverføring | Sikkerhetskopi (iCloud/iTunes) | Blokker | `dataBackupBlocked` |
| | Send organisasjonsdata til | Policy-administrerte apper | `allowedOutboundDataTransferDestinations = managedApps` |
| | Motta data fra | Alle apper (nivå 3: administrerte) | `allowedInboundDataTransferSources = allApps` |
| | Lagre kopier | Blokker, unntatt OneDrive for Business, SharePoint, bilder | `saveAsBlocked`, `allowedDataStorageLocations` |
| | Klipp ut/kopier/lim inn | Administrerte apper med innliming | `allowedOutboundClipboardSharingLevel = managedAppsWithPasteIn` |
| | Lenker | Microsoft Edge | `managedBrowser = microsoftEdge` |
| | Varsler | Skjul organisasjonsdata | `notificationRestriction = blockOrganizationalData` |
| Kryptering | iOS-databeskyttelse | Når enheten er låst | `appDataEncryptionType = whenDeviceLocked` |
| Tilgang | PIN | Påkrevd, numerisk, **6 sifre, ikke enkel** (avvik: nivå 3) | `pinRequired`, `minimumPinLength`, `simplePinBlocked` |
| | Face ID / Touch ID | Tillatt, PIN igjen etter 1440 min | `faceIdBlocked`, `fingerprintBlocked`, `pinRequiredInsteadOfBiometricTimeout` |
| | App-PIN når enheten har kode | Påkrevd | `disableAppPinIfDevicePinIsSet = false` |
| | Ny kontroll etter inaktivitet | 30 min | `periodOnlineBeforeAccessCheck` |
| Betinget start | Maks PIN-forsøk | 5, blokker | `maximumPinRetries`, `appActionIfMaximumPinRetriesExceeded` |
| | Frakoblet | Blokker etter 720 min (strengere enn rammeverkets 7 dager), **selektiv tømming etter 30 dager** | `periodOfflineBeforeAccessCheck`, `periodOfflineBeforeWipeIsEnforced` |
| | Deaktivert konto | Blokker | `appActionIfUnableToAuthenticateUser` |
| | Jailbreak | Blokker | `deviceComplianceRequired` |
| | Min. iOS-versjon | 18.0 (N-1), advarsel under 26.0 | `minimumRequiredOsVersion`, `minimumWarningOsVersion` |

Dette er bare på iOS og finnes ikke på Android: dataklasse-kryptering, Face ID, tredjepartstastatur (`thirdPartyKeyboardsBlocked`) og Open-In-filtrering.

## 6. Script og Graph

| Script | Gjør | Graph |
| --- | --- | --- |
| [`New-IntuneIosAppProtectionPolicy.ps1`](../apps/mobile-ios/New-IntuneIosAppProtectionPolicy.ps1) | Oppretter iOS-APP (hopper over hvis navnet finnes), setter målapper, filter og tildeling | beta `iosManagedAppProtections`, `managedAppPolicies/{id}/targetApps` og `/assign`, `assignmentFilters` |
| [`New-IntuneIosStoreOrLobApp.ps1`](../apps/mobile-ios/New-IntuneIosStoreOrLobApp.ps1) | App Store-app, VPP-app, webklipp eller eksisterende LOB-app + tildeling. Sjekker APNs og VPP-token. | `mobileApps` (beta for `iosStoreApp`), `mobileApps/{id}/assignments`, `applePushNotificationCertificate`, `vppTokens` |
| [`Get-IntunePreDeploymentReport.ps1`](../apps/inventory/Get-IntunePreDeploymentReport.ps1) | Leser status: APNs, ADE, brukerinitierte profiler, VPP, apper, APP | Se rapportens README |

Ærlig om usikkerhet:
- LOB-opplasting av `.ipa` er ikke scriptet. Den krever lesing av pakke og profil og innholdsopplasting i flere steg. Last opp i admin-senteret, og tildel med scriptet (`-AppId`).
- Noen APP-felt finnes bare i Graph beta og kan endres.

## Kilder

- [Create MDM push certificate](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/create-mdm-push-certificate)
- [Set up automated device enrollment](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-automated-ios)
- [Authentication methods for ADE](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/ref-automated-authentication-methods)
- [Account driven Apple User Enrollment](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-account-driven-user)
- [User enrollment with Company Portal (ikke for nye)](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-user-company-portal)
- [Manage Apple volume-purchased apps](https://learn.microsoft.com/en-us/intune/app-management/deployment/manage-vpp-apple)
- [Add iOS/iPadOS LOB app](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-lob-ios)
- [Data protection framework](https://learn.microsoft.com/en-us/intune/app-management/protection/data-protection-framework)
- [Create and assign app protection policies](https://learn.microsoft.com/en-us/intune/app-management/protection/create-policy)
- [Graph: iosManagedAppProtection (beta)](https://learn.microsoft.com/en-us/graph/api/resources/intune-mam-iosmanagedappprotection?view=graph-rest-beta)
- [Graph: iosStoreApp](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-iosstoreapp?view=graph-rest-1.0) · [iosVppApp](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-iosvppapp?view=graph-rest-1.0)
