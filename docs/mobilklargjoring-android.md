# Android i Intune – klargjøring og appdistribusjon

Sjekket mot Microsoft Learn 10. november 2026 (Europe/Oslo). iPhone/iOS er beskrevet separat i [mobilklargjoring-ios.md](mobilklargjoring-ios.md).

## 1. Forutsetninger (kan ikke scriptes)

| Forutsetning | Hvor | Merknad |
| --- | --- | --- |
| **Managed Google Play-kobling** | Devices > Enrollment > Android > Prerequisites > Managed Google Play | Godta datadeling, *Launch Google*, logg på med en **Entra-konto med postkasse** (anbefalt fra august 2024, i stedet for Gmail). Krever Intune-administrator eller organisasjonsrettighet for lesing/oppdatering. Google anbefaler minst to eiere. |
| Zero-touch-portal (valgfritt) | Google zero-touch via forhandler | Anbefalt for masseregistrering av firmaeide enheter |
| Registreringsbegrensninger | Devices > Enrollment > Device platform restriction | Tillat Android Enterprise work profile ved behov. **Blokker Android device administrator.** |

Scriptet `New-IntuneAndroidManagedPlayOrLobApp.ps1` leser `bindStatus` og stopper hvis tenanten ikke er koblet. Uten koblingen kan ingen Play-apper godkjennes eller tildeles.

## 2. Enrollment-metoder

| Metode | Eierskap | Når | Merknad |
| --- | --- | --- | --- |
| **Personally owned work profile** | Privat | BYOD | Egen jobbprofil, private data holdes atskilt. Brukeren registrerer med **Company Portal**. Android 10+. |
| **Corporate-owned work profile** (COPE) | Firma | Firmaenhet som også brukes privat | Registreres med Microsoft Intune-appen |
| **Fully managed** (COBO) | Firma | Firmaenhet bare for jobb, én bruker | Full styring. Zero-touch, QR eller token. |
| **Dedikert** (COSU) | Firma | Kiosk, skanner, delt enhet | Ingen fast bruker. Entra delt modus som tillegg. APP støttes bare med delt modus. Android 8+. |
| AOSP (med/uten bruker) | Firma | Enheter uten Google Mobile Services (for eksempel VR, Teams-enheter) | Spesialtilfelle |
| **Bare APP (MAM-WE)** | Privat | BYOD uten enrollment | Company Portal må likevel være installert |
| ~~Android device administrator~~ | – | **Ikke bruk** | Avviklet og ikke tilgjengelig på enheter med Google Mobile Services (fra desember 2024) |

## 3. Intune Company Portal på Android

- **Alltid påkrevd for APP på Android**, også uten enrollment. Company Portal er også megler-appen for Conditional Access.
- **Personally owned work profile:** brukeren installerer Company Portal fra Google Play og registrerer derfra.
- **Fully managed, COPE og dedikert:** Microsoft Intune-appen, Microsoft Authenticator og Company Portal installeres automatisk som påkrevde apper.

## 4. Appdistribusjon på Android

| Type | Graph-type | Når | Krav |
| --- | --- | --- | --- |
| **Managed Google Play – offentlig app** | `androidManagedStoreApp` | Standard for all Android Enterprise | Godkjennes i Managed Google Play og synkroniseres: Apps > All Apps > Create > Managed Google Play app > Select > Sync |
| Managed Google Play – privat app | `androidManagedStoreApp` (`isPrivate`) | Egne apper til work profile og firmaenheter | Last opp `.apk` under *Private apps* i Managed Google Play-vinduet, eller i Play Console |
| Managed Google Play – nettapp | `androidManagedStoreWebApp` | Web-lenker som app | Visningsmodusene virker bare i Chrome. Distribuer en nettleser. |
| Direkte LOB (.apk) | `androidLobApp` | Egne apper uten Play | **Bare fully managed og dedikerte enheter** |
| Android-butikkapp | `androidStoreApp` | Ikke for Android Enterprise | Vanlig Play-lenke (gammel modell) |

Intent:
- **Required** installeres stille i work profile eller på firmaenheten.
- **Available** vises i Managed Google Play-butikken i jobbprofilen.
- **Uninstall** fjerner appen.
- Oppdateringsprioritet og produksjons- eller testspor settes på tildelingen i admin-senteret.

## 5. App-beskyttelse (APP / MAM) på Android

Opprettes under **Apps > Protection > Create policy > Android**. Scriptet `New-IntuneAndroidAppProtectionPolicy.ps1` lager tilsvarende policy med Graph.

### Med og uten enrollment

- **Uten enrollment (MAM-WE):** brukergruppe med filteret `(app.deviceManagementType -eq "Unmanaged")` som **Include**.
- **Registrerte enheter:** samme filter som **Exclude**.
- På personlig work profile skiller profilen allerede jobb og privat. Mange bruker derfor lettere DLP-regler der enn på helt uadministrerte enheter.
- Ikke støttet: dedikerte enheter uten Entra delt modus.

### Anbefalte innstillinger (scriptets standard)

Grunnlag: Microsofts nivå 2 «Enterprise enhanced». Avvik er markert.

| Område | Innstilling | Verdi | Graph-felt |
| --- | --- | --- | --- |
| Dataoverføring | Sikkerhetskopi | Blokker | `dataBackupBlocked` |
| | Send organisasjonsdata til | Policy-administrerte apper | `allowedOutboundDataTransferDestinations = managedApps` |
| | Motta data fra | Alle apper (nivå 3: administrerte) | `allowedInboundDataTransferSources = allApps` |
| | Lagre kopier | Blokker, unntatt OneDrive for Business, SharePoint, bilder | `saveAsBlocked`, `allowedDataStorageLocations` |
| | Klipp ut/kopier/lim inn | Administrerte apper med innliming | `allowedOutboundClipboardSharingLevel = managedAppsWithPasteIn` |
| | **Skjermbilde og Google Assistant** | Blokker | `screenCaptureBlocked` |
| | Lenker / varsler | Edge / skjul organisasjonsdata | `managedBrowser`, `notificationRestriction` |
| Kryptering | Krypter organisasjonsdata | Påkrevd, også på registrerte enheter | `encryptAppData = true`, `disableAppEncryptionIfDeviceEncryptionIsEnabled = false` |
| Tilgang | PIN | Påkrevd, numerisk, **6 sifre, ikke enkel** (avvik: nivå 3) | `pinRequired`, `minimumPinLength`, `simplePinBlocked` |
| | Biometri | Tillatt, PIN igjen etter 1440 min | `fingerprintBlocked`, `biometricAuthenticationBlocked`, `pinRequiredInsteadOfBiometricTimeout` |
| | Ny kontroll etter inaktivitet | 30 min | `periodOnlineBeforeAccessCheck` |
| Betinget start | Maks PIN-forsøk | 5, blokker | `maximumPinRetries` |
| | Frakoblet | Blokker etter 720 min, **selektiv tømming etter 30 dager** | `periodOfflineBeforeAccessCheck`, `periodOfflineBeforeWipeIsEnforced` |
| | Deaktivert konto | Blokker | `appActionIfUnableToAuthenticateUser` |
| | Rootet enhet | Blokker | `deviceComplianceRequired` |
| | **Play Integrity** | Grunnleggende integritet og sertifisert enhet, **maskinvarebasert** evaluering (test først) | `requiredAndroidSafetyNetDeviceAttestationType`, `requiredAndroidSafetyNetEvaluationType` (Graph-navnene heter fortsatt SafetyNet) |
| | **Verify Apps** | Påkrevd | `requiredAndroidSafetyNetAppsVerificationType = enabled` |
| | **Enhetslås** | Minst middels kompleksitet, ellers blokker | `appActionIfDevicePasscodeComplexityLessThanMedium = block` |
| | Min. Android / patchnivå | 12.0 / valgfritt (ÅÅÅÅ-MM-DD) | `minimumRequiredOsVersion`, `minimumRequiredPatchVersion` |

Dette er bare på Android og finnes ikke på iOS: skjermbildeblokkering, Play Integrity, Verify Apps, enhetslås med kompleksitet, patchnivå, godkjente tastatur og Samsung Knox-attestasjon. Knox er ikke satt i scriptet fordi den gjelder alle målrettede enheter; bruk heller en egen policy med filter på produsent.

## 6. Script og Graph

| Script | Gjør | Graph |
| --- | --- | --- |
| [`New-IntuneAndroidAppProtectionPolicy.ps1`](../apps/mobile-android/New-IntuneAndroidAppProtectionPolicy.ps1) | Oppretter Android-APP (hopper over hvis navnet finnes), målapper, filter og tildeling | beta `androidManagedAppProtections`, `managedAppPolicies/{id}/targetApps` og `/assign`, `assignmentFilters` |
| [`New-IntuneAndroidManagedPlayOrLobApp.ps1`](../apps/mobile-android/New-IntuneAndroidManagedPlayOrLobApp.ps1) | Sjekker Managed Google Play-kobling, finner (eller godkjenner og synker) Play-app, tildeler. Kan også tildele eksisterende LOB-app. | beta `mobileApps` og `assignments` (`androidManagedStoreApp` er bare dokumentert i beta), `androidManagedStoreAccountEnterpriseSettings` (+ `approveApps`, `syncApps`) |
| [`Get-IntunePreDeploymentReport.ps1`](../apps/inventory/Get-IntunePreDeploymentReport.ps1) | Leser Managed Google Play-status, Android Enterprise-profiler, begrensninger, apper og APP | Se rapportens README |

Ærlig om usikkerhet:
- `approveApps` er dokumentert i Graph beta, men Microsofts hovedvei er godkjenning i admin-senteret. Bruk `-ApproveAndSync -ApproveAllPermissions` bevisst.
- Private apper og nettapper lages i Managed Google Play-vinduet, ikke med Graph.
- Personlig work profile har ingen egen profil i Graph. Den styres av koblingen og registreringsbegrensningene.

## Kilder

- [Connect Intune to managed Google Play](https://learn.microsoft.com/en-us/intune/device-enrollment/android/connect-managed-google-play)
- [Android enrollment guide](https://learn.microsoft.com/en-us/intune/device-enrollment/android/guide)
- [Personally owned work profile](https://learn.microsoft.com/en-us/intune/device-enrollment/android/setup-personal-work-profile)
- [Enroll devices (Android-metoder, avvikling av device administrator)](https://learn.microsoft.com/en-us/intune/device-enrollment/enroll-devices)
- [Add managed Google Play apps](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-managed-google-play)
- [Add Android LOB app](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-lob-android)
- [App protection overview (Company Portal påkrevd)](https://learn.microsoft.com/en-us/intune/app-management/protection/overview)
- [Android app protection settings](https://learn.microsoft.com/en-us/intune/app-management/protection/ref-settings-android)
- [Data protection framework](https://learn.microsoft.com/en-us/intune/app-management/protection/data-protection-framework)
- [Graph: androidManagedAppProtection (beta)](https://learn.microsoft.com/en-us/graph/api/resources/intune-mam-androidmanagedappprotection?view=graph-rest-beta)
- [Graph: androidManagedStoreApp (beta)](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-androidmanagedstoreapp?view=graph-rest-beta)
- [Graph: androidManagedStoreAccountEnterpriseSettings (beta)](https://learn.microsoft.com/en-us/graph/api/resources/intune-androidforwork-androidmanagedstoreaccountenterprisesettings?view=graph-rest-beta)
