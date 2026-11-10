# Anbefalte Slack Enterprise-innstillinger (til Confluence)

Dokumentasjon til Slack MSIX-utrullingen i Intune. Kildene er offisiell Slack-hjelp, sjekket 10. november 2026 (Europe/Oslo). Stiene under gjelder **Enterprise-planer** (organisasjonsdashbord). Har dere Business+, styres det meste under **Admin → Workspace settings** i stedet, og dere har ikke eget org-dashbord eller domenekrav.

## Slik åpner du adminområdet

På skrivebordet: klikk organisasjonsnavnet øverst til venstre → **Tools & settings** → **Organization settings**.

Alt du setter her gjelder som regel hele organisasjonen. Workspace-spesifikke unntak styres per arbeidsområde.

Kilde: [Guide to the Slack admin dashboard](https://slack.com/help/articles/115005594006-Guide-to-the-Slack-Admin-dashboard)

## Viktigste innstillinger

### 1. Eget workspace for ansatte

**Hvor:** Organization settings → **Organization** → **Workspaces** → **Create a Workspace**

Velg navn, domene, beskrivelse og hvordan medlemmer i organisasjonen skal få tilgang. Org Primary Owner blir automatisk eier av nye workspaces.

**Anbefaling:** Ett primært ansatt-workspace (eller en tydelig workspace-modell), med styrt tilgang. Ikke la alle fritt opprette nye workspaces uten prosess.

Kilde: [Create a workspace in an Enterprise organization](https://slack.com/help/articles/115001344007-Create-a-workspace-in-an-Enterprise-organization)

### 2. Reserver firmadomenet (domain claiming)

**Hvor:** Dette gjøres ikke i menyen. Org-eier kontakter [Slack Support](https://slack.com/help/requests/new) og ber om å *claim* selskapets e-postdomener.

**Hvorfor:** Hindrer at noen lager uautoriserte Slack-workspaces utenfor organisasjonen, og gjør det enklere for ansatte å finne riktig workspace.

Tilpass kontakt-e-post for folk som treffer det reserverte domenet: Organization settings → **Settings** → **Organization settings** → **Organization contact email**.

Kilde: [Claim domains for an Enterprise organization](https://slack.com/help/articles/115001379947-Claim-domains-for-an-Enterprise-organization)

### 3. SSO / SAML (påkrevd på Enterprise)

**Hvor:** Organization settings → **Security** → **SSO Settings**

Sett opp SAML mot identitetsleverandøren (typisk Microsoft Entra ID): SSO-navn, SAML 2.0 Endpoint URL, Identity Provider Issuer URL, X.509-sertifikat. Bruk **Test Configuration** før du slår på SSO.

**Anbefaling:**

- Krev SSO for alle ansatte.
- La gjester fortsatt kunne logge inn med e-post og passord (delvis krav), slik at de ikke blir stengt ute.
- Synk profiler fra IdP, og lås at brukere selv endrer e-post og visningsnavn.
- Sørg for at e-postadressene i Entra ID matcher Slack-kontoene før SSO slås på.

Kilder:

- [Set up SAML single sign-on for Slack](https://slack.com/help/articles/203772216-Set-up-SAML-single-sign-on-for-Slack)
- [Manage single sign-on settings](https://slack.com/help/articles/220403548-Manage-single-sign-on-settings)
- [Enterprise organization launch guide](https://slack.com/help/articles/115005481226-Enterprise-organization-launch-guide) (SSO er påkrevd på Enterprise-planer)

### 4. SCIM-brukerstyring mot Entra ID

**Hvor:** Settes opp i identitetsleverandøren (Microsoft Entra) med API-token fra Slack. Slack støtter Entra offisielt.

**Anbefaling:** Automatiser oppretting og deaktivering av ansatte (og gjester der det er aktuelt), slik at sluttede brukere mister tilgang uten manuell rydding.

Kilde: [Manage members with SCIM provisioning](https://slack.com/help/articles/212572638-Manage-members-with-SCIM-provisioning)

### 5. Øktvarighet og mobil sikkerhet

**Hvor:** Organization settings → **Security** → **Security settings**

- **Desktop session duration** og **Mobile session duration:** begrens hvor lenge folk er innlogget.
- Krev sekundær autentisering på mobil (passkode, fingeravtrykk eller ansiktsgjenkjenning).

Hvis noen kontotyper fortsatt bruker passord (typisk gjester uten SSO), vurder obligatorisk 2FA i tillegg. For ansatte på SSO bør MFA ligge i Entra ID.

Kilder:

- [Manage session duration](https://slack.com/help/articles/115005223763-Manage-session-duration)
- [Require a mobile passcode](https://slack.com/help/articles/360033808693-Require-a-mobile-passcode)

### 6. Godkjenning av apper og integrasjoner

**Hvor:** Organization settings → **Integrations** → **Manage Apps**

Her kan du installere apper på org-nivå, godkjenne apper workspace-eiere får lov til å installere, eller blokkere apper.

**Anbefaling:** Krev appgodkjenning. Ikke la ansatte fritt installere tredjepartsapper.

Kilde: [Manage apps in an Enterprise organization](https://slack.com/help/articles/360000281563-Manage-apps-in-an-Enterprise-organization)

### 7. Gjester og Slack Connect

**Hvor:**

- Hvem som kan invitere gjester: Organization settings → **Roles & permissions** → **Account types** → **Manage guest invitation requests**
- Maks varighet for gjester: Organization settings → **Settings** → **Organization settings** → **Maximum expiration for guests**

**Anbefaling:** Begrens hvem som kan invitere gjester, sett en maks utløpstid, og bruk Slack Connect til eksternt samarbeid i stedet for å gi partnere full tilgang til ansatt-workspacet.

Kilde: [Manage who can invite guests in an Enterprise organization](https://slack.com/help/articles/115003717963-Manage-who-can-invite-guests-in-an-Enterprise-organization)

### 8. Lagringstid for meldinger og filer

**Hvor:** Organization settings → **Settings** (message and file retention)

Sett en tydelig retensjonspolicy som matcher intern arkiv- og slettepraksis. Enterprise har også Discovery API, audit logs og ev. DLP ved behov.

### 9. Skrivebordsapp ved Intune/MSIX: DefaultSignInTeam og AutoUpdate

Disse to innstillingene settes **ikke** i Slack Admin, og Slack dokumenterer **ikke** et eget Intune-profilnavn for dem. Offisiell Slack-dokumentasjon sier at skrivebordsinnstillingene settes med **Windows Group Policy**, ved hjelp av Slacks [Group Policy Object-mal](https://slack.zendesk.com/hc/en-us/article_attachments/37504463164819) (lastes ned fra artikkelen under), eller ved å skrive de samme verdiene i registeret. Begge innstillingene er **Enforced** (påtvunget). HKLM går foran HKCU hvis begge er satt. Krever Slack-skrivebordsapp 4.31 eller nyere.

Etter at `slack.admx` / `slack.adml` er importert, er stien i gpedit eller Group Policy Management:

- Datamaskinkonfigurasjon (anbefalt ved MSIX i enhetskontekst) eller brukerkonfigurasjon
- **Administrative Templates → Slack**

Konkrete innstillinger:

| Innstilling | Visningsnavn i GPO-malen | Registersti (Enforced) | Type og verdi |
|---|---|---|---|
| AutoUpdate | **Auto Update** | `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Slack\AutoUpdate` (alternativt HKCU) | REG_DWORD: `1` = på, `0` = av |
| DefaultSignInTeam | **Default SignIn Team** | `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Slack\DefaultSignInTeam` (alternativt HKCU) | REG_SZ: gyldig workspace-ID (starter på T) eller org-ID (starter på E) |

**Anbefaling sammen med MSIX-utrullingen:** sett DefaultSignInTeam til org- eller workspace-ID, og la AutoUpdate stå på (`1`). Finn ID slik Slack beskriver i [Locate your Slack URL or ID](https://slack.com/help/articles/221769328-locate-your-slack-url-or-id).

Intune kan brukes til å *distribuere* MSIX, men selve disse to innstillingene er likevel GPO/registerverdiene over. Dere kan pushe de samme registerverdiene fra Intune; det finnes ikke et Slack-navngitt konfigurasjonsprofil i den offisielle dokumentasjonen.

Kilder:

- [Manage desktop app configurations](https://slack.com/help/articles/11906214948755-Manage-desktop-app-configurations)
- [Deploy Slack for Windows](https://slack.com/help/articles/212475728-Deploy-Slack-for-Windows)
- Offisiell GPO-mal (slack.admx): [nedlasting fra Slack](https://slack.zendesk.com/hc/en-us/article_attachments/37504463164819)
