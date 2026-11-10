# Mobilklargjøring i Intune – oversikt (iPhone/iOS og Android)

Sjekket mot Microsoft Learn 10. november 2026 (Europe/Oslo). Menynavn i Intune admin center endres jevnlig. Stiene under er slik Microsoft dokumenterer dem nå.

Detaljer per plattform:
- [iPhone/iOS i dybden](mobilklargjoring-ios.md)
- [Android i dybden](mobilklargjoring-android.md)

Script: [`apps/mobile-ios`](../apps/mobile-ios/README.md), [`apps/mobile-android`](../apps/mobile-android/README.md) og [forutsetningsrapporten](../apps/inventory/README.md).

## To modeller, begge plattformer

| Modell | Hva Intune styrer | Typisk bruk |
| --- | --- | --- |
| **App-beskyttelse uten enrollment (MAM-WE / APP uten MDM)** | Bare organisasjonsdata i støttede apper (Outlook, Teams, Edge, OneDrive osv.) | Private telefoner (BYOD) |
| **Enrollment (MDM) + app-beskyttelse** | Enheten (samsvar, konfigurasjon, apper) og dataene i appene | Firmaeide telefoner, og BYOD der dere vil distribuere apper |

App-beskyttelsespolicyer (APP) tildeles **brukere**. Med et filter for administrerte apper (`app.deviceManagementType`) kan samme bruker få én policy på private enheter og en annen på registrerte enheter.

## Anbefalte trinn

1. **Kjør forutsetningsrapporten** (`Get-IntunePreDeploymentReport.ps1`) og gå gjennom «Funn».
2. **Lag pilotgrupper** etter konvensjonen `Pilot - <produkt> <teknologi> - <mål>`, for eksempel `Pilot - Mobil APP - Brukere`. `New-EntraSlackMsixPilotGroup.ps1` kan gjenbrukes med `-DisplayName`, `-MailNickname` og `-Description`.
3. **App-beskyttelse først** (virker uten enrollment):
   - iOS: `New-IntuneIosAppProtectionPolicy.ps1`
   - Android: `New-IntuneAndroidAppProtectionPolicy.ps1`
   - Standard er Microsofts nivå 2 «Enterprise enhanced», med PIN fra nivå 3.
4. **Plattformforutsetninger som ikke kan scriptes:**
   - iOS: Apple MDM Push-sertifikat (APNs), Apple Business med ADE-token og VPP-/plasseringstoken.
   - Android: koble Intune til Managed Google Play.
5. **Enrollment-metode per eierskap** (se tabellene under), og registreringsbegrensninger: blokker Android device administrator.
6. **Samsvarspolicyer** per plattform og registreringstype, deretter Conditional Access («Krev app-beskyttelsespolicy» og/eller «Krev samsvarende enhet»).
7. **Apper:**
   - iOS: App Store / VPP / LOB med `New-IntuneIosStoreOrLobApp.ps1`
   - Android: Managed Google Play med `New-IntuneAndroidManagedPlayOrLobApp.ps1`
8. **Pilot, kontroll, utvidelse.** Kjør rapporten på nytt, sammenlign og utvid gruppene.

## iPhone/iOS kort

| Tema | Anbefaling |
| --- | --- |
| Firmaeide | **Automatisert enhetsregistrering (ADE)** via Apple Business, med brukeraffinitet og *Setup Assistant med moderne autentisering* + JIT-registrering. Legacy Setup Assistant ble pensjonert i oktober 2026 (2610). |
| Private (BYOD) | **Kontobasert brukerregistrering** (Account Driven User Enrollment, iOS 15+), eller bare APP uten enrollment |
| Ikke for nye | «User enrollment with Company Portal» støttes ikke for nye registreringer |
| Company Portal | ADE: distribuer som **VPP-app via Intune**, ikke fra App Store. Kontobasert: Company Portal-**nettapp**. MAM-WE: trengs ikke, men **Microsoft Authenticator** er megler for Conditional Access. |
| Apper | App Store (`iosStoreApp`), **VPP med enhetslisens** (`iosVppApp`), LOB `.ipa` (`iosLobApp`), webklipp |
| APP-særtrekk | Kryptering med iOS-databeskyttelsesklasse. Registrerte enheter må få `IntuneMAMUPN`/`IntuneMAMOID` via app-konfigurasjon for å regnes som administrert. |

## Android kort

| Tema | Anbefaling |
| --- | --- |
| Forutsetning | Intune koblet til **Managed Google Play** (Entra-konto med postkasse) |
| Firmaeide, kun jobb | **Fully managed** (COBO), helst med zero-touch for masseutrulling |
| Firmaeide, også privat bruk | **Corporate-owned work profile** (COPE) |
| Kiosk/delt | **Dedikert enhet** (COSU), eventuelt med Entra delt modus |
| Private (BYOD) | **Personally owned work profile**, eller bare APP uten enrollment |
| Ikke bruk | **Android device administrator**: avviklet på enheter med Google Mobile Services |
| Company Portal | **Påkrevd for APP**, også uten enrollment, og megler for Conditional Access. Brukes også ved registrering av personlig work profile. Firmaeide bruker Microsoft Intune-appen; Company Portal installeres automatisk. |
| Apper | **Managed Google Play**: offentlige, private (`.apk`/`.aab`) og nettapper. Direkte LOB `.apk` bare på fully managed og dedikerte. |
| APP-særtrekk | Blokker skjermbilde, krev Play Integrity og enhetslås, og sjekk sikkerhetsoppdateringsnivå |

## Forskjeller mellom iOS og Android

| Område | iPhone/iOS | Android |
| --- | --- | --- |
| Grunnmur | APNs-sertifikat (fornyes årlig med samme Apple-konto) | Managed Google Play-kobling |
| Firmaeide | ADE (Apple Business) | Fully managed / COPE / dedikert (zero-touch, QR, token) |
| BYOD med enrollment | Kontobasert brukerregistrering | Personally owned work profile |
| Megler for APP/Conditional Access | Microsoft Authenticator | Company Portal (alltid påkrevd for APP) |
| Lisensierte apper | VPP (Apple Business, Apps and Books) | Managed Google Play-godkjenning |
| Egne apper | LOB `.ipa` med provisjoneringsprofil (utløper) | Private apper i Managed Google Play; direkte `.apk` bare på fully managed/dedikert |
| APP-kryptering | `appDataEncryptionType` (iOS-dataklasse) | `encryptAppData` |
| APP bare på én plattform | Face ID, tredjepartstastatur | Skjermbilde, Play Integrity, enhetslås, patchnivå, godkjente tastatur |

## Forskjell fra Windows-utrulling med LOB-app (Slack MSIX)

| | Windows (Slack MSIX) | Mobil (iOS/Android) |
| --- | --- | --- |
| Pakke | Egen MSIX lastes opp som LOB, enhetskontekst | Vanligvis butikkapp (App Store/VPP eller Managed Google Play). LOB er unntak. |
| Mål | **Enhetsgruppe**, Required (Available + enhetskontekst er ikke tillatt) | Ofte **brukergrupper** (Available rettes mot brukere) |
| Uten enrollment | Ikke aktuelt for LOB | APP beskytter data i apper på private enheter uten MDM |
| Oppdatering | Ny pakkeversjon lastes opp (eller Slack AutoUpdate) | Butikken oppdaterer. LOB krever ny `.ipa`/`.apk`; iOS-profilen utløper. |
| Forutsetninger | Windows Pro/Enterprise, Intune-lisens | APNs + Apple Business (iOS) / Managed Google Play (Android) |
| Rydding | Gammel MSI må fjernes før MSIX | Ikke relevant. Selektiv tømming fjerner bare organisasjonsdata. |

## Kilder (Microsoft Learn)

- [Data protection framework (APP nivå 1–3)](https://learn.microsoft.com/en-us/intune/app-management/protection/data-protection-framework)
- [Opprette og tildele app-beskyttelsespolicyer](https://learn.microsoft.com/en-us/intune/app-management/protection/create-policy)
- [Oversikt over app-beskyttelse](https://learn.microsoft.com/en-us/intune/app-management/protection/overview)
- [Filteregenskaper (app.deviceManagementType)](https://learn.microsoft.com/en-us/intune/fundamentals/filters/ref-device-properties)
- [Conditional Access – grant controls](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-grant)
- [Enroll devices (alle plattformer)](https://learn.microsoft.com/en-us/intune/device-enrollment/enroll-devices)
- [Android enrollment guide](https://learn.microsoft.com/en-us/intune/device-enrollment/android/guide)
- [Set up automated device enrollment (iOS)](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-automated-ios)
- [Account driven Apple User Enrollment](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-account-driven-user)
- [Add apps to Intune](https://learn.microsoft.com/en-us/intune/app-management/deployment/)
- [Windows-appdistribusjon (MSIX-krav)](https://learn.microsoft.com/en-us/intune/app-management/deployment/deploy-windows)
