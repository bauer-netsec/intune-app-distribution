#Requires -Version 5.1
# UTF-8 med BOM, slik at æ/ø/å vises riktig også i Windows PowerShell 5.1.
<#
.SYNOPSIS
    Oppretter en Android app-beskyttelsespolicy (APP/MAM) i Intune med sikre standardvalg.

.DESCRIPTION
    Scriptet oppretter én Android app-beskyttelsespolicy basert på Microsofts rammeverk
    for databeskyttelse, nivå 2 «Enterprise enhanced», med strengere PIN fra nivå 3.
    Hvert valg er forklart i kommentarene i New-PolicyBody.

    Policyen finnes bare én gang: finnes en Android-policy med samme visningsnavn, hopper
    scriptet over oppretting (ingen duplikater).

    Med eller uten enrollment (MAM-WE):
      -DeviceManagementScope Unmanaged  Bare Android-enheter uten Intune-MDM (BYOD, MAM-WE).
                                        Standard. Filter (app.deviceManagementType -eq "Unmanaged")
                                        som Include.
      -DeviceManagementScope Managed    Bare Intune-registrerte enheter (Android Enterprise
                                        work profile, fully managed, COPE osv.). Samme filter
                                        som Exclude.
      -DeviceManagementScope All        Alle enheter, uten filter.

    Android-spesifikt (skiller seg fra iOS):
      - Intune Company Portal MÅ være installert på enheten for at Android skal motta APP,
        også uten enrollment. Company Portal er også megler-appen for Conditional Access.
      - Kryptering styres med encryptAppData (og på registrerte enheter med
        disableAppEncryptionIfDeviceEncryptionIsEnabled), ikke iOS-databeskyttelsesklasser.
      - Skjermbilde og Google Assistant kan blokkeres (screenCaptureBlocked).
      - Enhetsintegritet sjekkes med Google Play Integrity (Graph-feltene heter fortsatt
        «SafetyNet»), og Verify Apps-skanning kan kreves.
      - Enhetslås med kompleksitet kan kreves (appActionIfDevicePasscodeComplexityLessThanMedium).
      - På personlige enheter med Android Enterprise work profile gjelder APP for appene i
        work profile. Mange velger der lettere DLP fordi work profile allerede skiller data.
      - Android Enterprise dedikerte enheter uten Shared device mode støtter ikke APP.

.PARAMETER DisplayName
    Visningsnavn. Standard: "APP - Android - Nivå 2 - <omfang>".

.PARAMETER Description
    Beskrivelse som lagres på policyen.

.PARAMETER DeviceManagementScope
    Unmanaged (standard, MAM uten enrollment), Managed eller All.

.PARAMETER UserGroupId
    Objekt-ID for brukergruppen. APP tildeles brukere, ikke enheter.

.PARAMETER UserGroupName
    Visningsnavn for brukergruppen hvis du ikke har ID. Krever Group.Read.All.

.PARAMETER SkipAssignment
    Opprett policyen uten å tildele den.

.PARAMETER AppGroupType
    allMicrosoftApps (standard), allCoreMicrosoftApps eller allApps. Ignoreres med -PackageIds.

.PARAMETER PackageIds
    Bestemte Android-pakkenavn, for eksempel egne apper med Intune SDK. Gir selectedPublicApps.

.PARAMETER MinimumRequiredOsVersion
    Laveste Android-versjon før tilgang blokkeres. Standard 12.0. Kontroller mot
    enhetsparken og Microsoft-appenes krav før produksjon.

.PARAMETER MinimumRequiredPatchVersion
    Eldste tillatte sikkerhetsoppdatering (ÅÅÅÅ-MM-DD). Valgfri. Nivå 2 anbefaler den,
    men sett den først når dere vet at enhetene faktisk får månedlige oppdateringer.

.PARAMETER PlayIntegrityEvaluationType
    hardwareBacked (standard, nivå 2) eller basic. Microsoft anbefaler å teste
    maskinvarebasert attestasjon på enhetene før bred utrulling, derfor kan den overstyres.

.PARAMETER UnmanagedFilterName
    Navn på filteret for uadministrerte Android-apper. Gjenbrukes hvis det finnes.

.PARAMETER TenantId
    Tenant-ID. Valgfri ved interaktiv pålogging, påkrevd sammen med sertifikat.

.PARAMETER ClientId
    App-registreringens program-ID ved app-only-pålogging med sertifikat.

.PARAMETER CertificateThumbprint
    Tommelavtrykk for sertifikatet i lokalt sertifikatlager. App-only, uten hemmelighet.

.EXAMPLE
    .\New-IntuneAndroidAppProtectionPolicy.ps1 -UserGroupName 'Pilot - Mobil APP - Brukere' -WhatIf

.EXAMPLE
    .\New-IntuneAndroidAppProtectionPolicy.ps1 -UserGroupId '<gruppe-id>' -DeviceManagementScope Unmanaged -MinimumRequiredPatchVersion '2026-08-01'

.EXAMPLE
    .\New-IntuneAndroidAppProtectionPolicy.ps1 -UserGroupId '<gruppe-id>' -DeviceManagementScope Managed -PlayIntegrityEvaluationType basic

.NOTES
    Minste Graph-rettigheter:
      - DeviceManagementApps.ReadWrite.All           (policy, målapper, tildeling)
      - DeviceManagementConfiguration.ReadWrite.All  (filter for administrerte apper; bare ved Unmanaged/Managed)
      - Group.Read.All                               (bare ved -UserGroupName)

    Hvorfor Graph beta:
      /beta/deviceAppManagement/androidManagedAppProtections brukes fordi blant annet
      notificationRestriction, appActionIfDevicePasscodeComplexityLessThanMedium,
      requiredAndroidSafetyNetEvaluationType, appActionIfUnableToAuthenticateUser og
      appGroupType bare finnes i beta. Tilsvarende cmdlet:
      New-MgBetaDeviceAppManagementAndroidManagedAppProtection (Microsoft.Graph.Beta).

    Samsung Knox-attestasjon (nivå 2) settes ikke her, fordi den gjelder alle målrettede
    enheter. Bruk heller en egen policy med filter på produsent hvis dere vil ha den.

    Kilder (sjekket 10. november 2026):
      https://learn.microsoft.com/en-us/intune/app-management/protection/data-protection-framework
      https://learn.microsoft.com/en-us/intune/app-management/protection/ref-settings-android
      https://learn.microsoft.com/en-us/intune/app-management/protection/create-policy
      https://learn.microsoft.com/en-us/intune/app-management/protection/overview
      https://learn.microsoft.com/en-us/intune/fundamentals/filters/ref-device-properties
      https://learn.microsoft.com/en-us/graph/api/resources/intune-mam-androidmanagedappprotection?view=graph-rest-beta
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ByGroupId')]
param(
    [string]$DisplayName,

    [string]$Description = 'Android app-beskyttelse etter Microsofts rammeverk nivå 2 (Enterprise enhanced), med PIN fra nivå 3. Opprettet med New-IntuneAndroidAppProtectionPolicy.ps1.',

    [ValidateSet('Unmanaged', 'Managed', 'All')]
    [string]$DeviceManagementScope = 'Unmanaged',

    [Parameter(ParameterSetName = 'ByGroupId')]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$UserGroupId,

    [Parameter(ParameterSetName = 'ByGroupName', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserGroupName,

    [switch]$SkipAssignment,

    [ValidateSet('allMicrosoftApps', 'allCoreMicrosoftApps', 'allApps')]
    [string]$AppGroupType = 'allMicrosoftApps',

    [ValidatePattern('^[A-Za-z0-9_\.]+$')]
    [string[]]$PackageIds,

    [ValidatePattern('^\d+(\.\d+){0,2}$')]
    [string]$MinimumRequiredOsVersion = '12.0',

    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$MinimumRequiredPatchVersion,

    [ValidateSet('hardwareBacked', 'basic')]
    [string]$PlayIntegrityEvaluationType = 'hardwareBacked',

    [string]$UnmanagedFilterName = 'Filter - Android MAM - Uadministrerte enheter',

    [string]$TenantId,

    [string]$ClientId,

    [string]$CertificateThumbprint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'

# Plattformverdier for Android. iOS-scriptet har egne verdier.
$script:PolicyCollection = 'androidManagedAppProtections'
$script:PolicyODataType = '#microsoft.graph.androidManagedAppProtection'
$script:FilterPlatform = 'androidMobileApplicationManagement'
$script:PlatformLabel = 'Android'
$script:PlatformShortName = 'Android'

# Egne apper (selectedPublicApps) for denne plattformen.
$script:CustomAppIds = @($PackageIds | Where-Object { $_ })
$script:CustomAppParamName = 'PackageIds'

# -----------------------------------------------------------------------------
# Felles hjelpefunksjoner (samme mønster i alle mobil- og rapportscript)
# -----------------------------------------------------------------------------
function Assert-AppOnlyParameterSet {
    <#
    .SYNOPSIS
        Stopper tidlig hvis bare noen av app-only-parametrene er satt.
    #>
    $supplied = @($TenantId, $ClientId, $CertificateThumbprint | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($supplied.Count -gt 0 -and $supplied.Count -lt 3) {
        throw "App-only-pålogging krever at -TenantId, -ClientId og -CertificateThumbprint brukes sammen. Ikke bruk klienthemmelighet."
    }
}

function Import-GraphAuthenticationModule {
    <#
    .SYNOPSIS
        Sikrer at Microsoft.Graph.Authentication er installert og lastet.
    .DESCRIPTION
        Scriptet kaller Graph-ressursene direkte med Invoke-MgGraphRequest. Da trengs bare
        denne ene modulen, og vi unngår versjonskonflikter mellom Microsoft.Graph- og
        Microsoft.Graph.Beta-undermoduler.
    #>
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Host "Installerer modulen Microsoft.Graph.Authentication i CurrentUser-omfang..."
        Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}

function Connect-IntuneGraph {
    <#
    .SYNOPSIS
        Kobler til Graph interaktivt med minste rettigheter, eller app-only med sertifikat.
    .NOTES
        Pålogging endrer ingenting i tenanten, derfor skjer den også ved -WhatIf.
        Da kan -WhatIf vise nøyaktig hva som ville blitt opprettet.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Scopes)

    if ($ClientId) {
        Write-Host "Kobler til Microsoft Graph med app-sertifikat (ingen klienthemmelighet)."
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome
        Write-Host "App-only: app-registreringen må ha disse programtillatelsene med administratorsamtykke: $($Scopes -join ', ')"
        return
    }

    $context = $null
    try { $context = Get-MgContext } catch { $context = $null }
    if ($context -and $context.Scopes) {
        # En ReadWrite-rettighet dekker også tilsvarende Read-rettighet.
        $missing = @($Scopes | Where-Object {
                ($context.Scopes -notcontains $_) -and ($context.Scopes -notcontains ($_ -replace '\.Read\.All$', '.ReadWrite.All'))
            })
        $sameTenant = (-not $TenantId) -or ($context.TenantId -eq $TenantId)
        if ($missing.Count -eq 0 -and $sameTenant) {
            Write-Host "Bruker eksisterende Graph-økt ($($context.TenantId))."
            return
        }
    }

    Write-Host "Kobler til Microsoft Graph interaktivt med rettighetene: $($Scopes -join ', ')."
    $connectParams = @{ Scopes = $Scopes; NoWelcome = $true }
    if ($TenantId) { $connectParams.TenantId = $TenantId }
    Connect-MgGraph @connectParams
}

function Invoke-Graph {
    <#
    .SYNOPSIS
        Tynn innpakning rundt Invoke-MgGraphRequest som alltid gir hashtabeller tilbake.
    #>
    param(
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method = 'GET',
        [Parameter(Mandatory = $true)][string]$Uri,
        $Body
    )
    $params = @{ Method = $Method; Uri = $Uri; OutputType = 'HashTable' }
    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
        $params.ContentType = 'application/json'
    }
    return Invoke-MgGraphRequest @params
}

function Get-GraphCollection {
    <#
    .SYNOPSIS
        Henter alle sider av en Graph-samling ved å følge @odata.nextLink.
    #>
    param([Parameter(Mandatory = $true)][string]$Uri)
    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri
    while ($next) {
        $response = Invoke-Graph -Uri $next
        if ($response -and $response.ContainsKey('value')) {
            foreach ($item in $response['value']) { $items.Add($item) }
        }
        $next = $null
        if ($response -and $response.ContainsKey('@odata.nextLink')) { $next = $response['@odata.nextLink'] }
    }
    return $items.ToArray()
}

function Get-Prop {
    <#
    .SYNOPSIS
        Leser en egenskap trygt. Ulike Graph-typer har ulike felt, og StrictMode skal ikke stoppe oss.
    #>
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Resolve-EntraGroupId {
    <#
    .SYNOPSIS
        Gir objekt-ID for en Entra-gruppe ut fra ID eller visningsnavn. Feiler ved null eller flere treff.
    #>
    param([string]$Id, [string]$Name)
    if ($Id) { return $Id }
    $safeName = $Name.Replace("'", "''")
    $uri = "$script:GraphV1/groups?`$filter=displayName eq '$safeName'&`$select=id,displayName"
    $groups = @(Get-GraphCollection -Uri $uri)
    if ($groups.Count -eq 0) { throw "Fant ingen Entra-gruppe med visningsnavn '$Name'." }
    if ($groups.Count -gt 1) {
        $list = ($groups | ForEach-Object { "$($_['displayName']) ($($_['id']))" }) -join ', '
        throw "Fant flere grupper med visningsnavn '$Name': $list. Bruk gruppe-ID i stedet."
    }
    Write-Host "Fant gruppen '$($groups[0]['displayName'])' ($($groups[0]['id']))."
    return [string]$groups[0]['id']
}

function ConvertTo-DateTimeOffsetValue {
    <#
    .SYNOPSIS
        Gjør Graph-tidsstempler om til DateTimeOffset uavhengig av regionale innstillinger.
    #>
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [DateTime]) {
        $utc = if ($Value.Kind -eq [DateTimeKind]::Unspecified) { [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc) } else { $Value.ToUniversalTime() }
        return [DateTimeOffset]$utc
    }
    return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
}


# -----------------------------------------------------------------------------
# Filter og tildeling for app-beskyttelse (samme logikk for iOS og Android,
# men plattformverdiene er satt øverst i hvert script)
# -----------------------------------------------------------------------------
function Get-OrNewUnmanagedAppFilter {
    <#
    .SYNOPSIS
        Finner eller oppretter filteret for administrerte apper som treffer uadministrerte enheter.
    .DESCRIPTION
        Regelen (app.deviceManagementType -eq "Unmanaged") er dokumentert for både Android og
        iOS/iPadOS. Det samme filteret brukes som Include (bare uten enrollment) eller
        Exclude (bare Intune-registrerte enheter).
    #>
    $rule = '(app.deviceManagementType -eq "Unmanaged")'
    $existing = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceManagement/assignmentFilters" |
            Where-Object { (Get-Prop $_ 'displayName') -eq $UnmanagedFilterName })

    if ($existing.Count -gt 1) {
        throw "Fant flere filtre med navnet '$UnmanagedFilterName'. Rydd opp i Intune (Tenant administration > Filters) først."
    }
    if ($existing.Count -eq 1) {
        $filter = $existing[0]
        if ((Get-Prop $filter 'platform') -ne $script:FilterPlatform -or (Get-Prop $filter 'rule') -ne $rule) {
            throw "Filteret '$UnmanagedFilterName' finnes, men har plattform '$(Get-Prop $filter 'platform')' og regel '$(Get-Prop $filter 'rule')'. Forventet $script:FilterPlatform og $rule. Bruk et annet -UnmanagedFilterName eller rett filteret."
        }
        Write-Host "Bruker eksisterende filter '$UnmanagedFilterName' ($(Get-Prop $filter 'id'))."
        return $filter
    }

    $body = @{
        displayName                    = $UnmanagedFilterName
        description                    = "Treffer $script:PlatformLabel-apper på enheter uten Intune-MDM. Brukes som Include for MAM uten enrollment og som Exclude for policyer til registrerte enheter."
        platform                       = $script:FilterPlatform
        rule                           = $rule
        assignmentFilterManagementType = 'apps'
    }
    if (-not $PSCmdlet.ShouldProcess($UnmanagedFilterName, 'Opprett filter for administrerte apper')) {
        Write-Host "WhatIf: ville opprettet filteret '$UnmanagedFilterName' med regelen $rule."
        return $null
    }
    Write-Host "Oppretter filter '$UnmanagedFilterName'..."
    return Invoke-Graph -Method POST -Uri "$script:GraphBeta/deviceManagement/assignmentFilters" -Body $body
}

function Add-AppProtectionAssignment {
    <#
    .SYNOPSIS
        Legger til én gruppetildeling og beholder alle eksisterende tildelinger.
    .DESCRIPTION
        assign-handlingen erstatter hele tildelingslisten. Vi leser derfor eksisterende
        tildelinger, hopper over hvis gruppen allerede har samme tildeling, og sender
        ellers hele listen tilbake med den nye i tillegg.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$PolicyId,
        [Parameter(Mandatory = $true)][string]$GroupId,
        [string]$FilterId,
        [ValidateSet('include', 'exclude', 'none')][string]$FilterType = 'none'
    )

    $current = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/$script:PolicyCollection/$PolicyId/assignments")
    $assignments = @()
    foreach ($a in $current) {
        $target = Get-Prop $a 'target'
        $assignments += @{
            '@odata.type' = '#microsoft.graph.targetedManagedAppPolicyAssignment'
            target        = $target
        }
        if ((Get-Prop $target 'groupId') -eq $GroupId -and (Get-Prop $target '@odata.type') -eq '#microsoft.graph.groupAssignmentTarget') {
            $sameFilter = ((Get-Prop $target 'deviceAndAppManagementAssignmentFilterId') -eq $FilterId) -or
                ((-not $FilterId) -and ((Get-Prop $target 'deviceAndAppManagementAssignmentFilterType') -in @($null, 'none')))
            if ($sameFilter) {
                Write-Host "Gruppen $GroupId er allerede tildelt med samme filter. Ingen endring i tildelinger."
                return
            }
            throw "Gruppen $GroupId er allerede tildelt policyen med et annet filter. Rett tildelingen i Intune manuelt, så scriptet ikke overskriver et bevisst valg."
        }
    }

    $newTarget = @{
        '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
        groupId       = $GroupId
    }
    if ($FilterId -and $FilterType -ne 'none') {
        $newTarget.deviceAndAppManagementAssignmentFilterId = $FilterId
        $newTarget.deviceAndAppManagementAssignmentFilterType = $FilterType
    }
    $assignments += @{
        '@odata.type' = '#microsoft.graph.targetedManagedAppPolicyAssignment'
        target        = $newTarget
    }

    $label = if ($FilterType -eq 'none') { 'uten filter' } else { "filter $FilterType" }
    if (-not $PSCmdlet.ShouldProcess("policy $PolicyId", "Tildel til gruppe $GroupId ($label)")) {
        Write-Host "WhatIf: ville tildelt policyen til gruppe $GroupId ($label)."
        return
    }
    Invoke-Graph -Method POST -Uri "$script:GraphBeta/deviceAppManagement/managedAppPolicies/$PolicyId/assign" -Body @{ assignments = $assignments } | Out-Null
    Write-Host "Tildelt til gruppe $GroupId ($label)."
}


# -----------------------------------------------------------------------------
# Android-spesifikke innstillinger
# -----------------------------------------------------------------------------
function New-PolicyBody {
    <#
    .SYNOPSIS
        Bygger policyobjektet med dokumenterte, konservative bedriftsverdier for Android.
    #>
    $body = [ordered]@{
        '@odata.type' = $script:PolicyODataType
        displayName   = $DisplayName
        description   = $Description

        # --- Dataoverføring (nivå 2) ---------------------------------------------------
        # Ingen sikkerhetskopi av organisasjonsdata til Android-backuptjenester.
        dataBackupBlocked                       = $true
        # Organisasjonsdata kan bare sendes til policy-administrerte apper.
        allowedOutboundDataTransferDestinations = 'managedApps'
        # Nivå 2 tillater mottak fra alle apper (nivå 3: managedApps).
        allowedInboundDataTransferSources       = 'allApps'
        # Blokker «Lagre som», men tillat OneDrive for Business, SharePoint og bildebibliotek.
        saveAsBlocked                           = $true
        allowedDataStorageLocations             = @('oneDriveForBusiness', 'sharePoint', 'photoLibrary')
        # Klipp ut/kopier bare mellom administrerte apper, lim inn fra alle.
        allowedOutboundClipboardSharingLevel    = 'managedAppsWithPasteIn'
        # Blokker skjermbilde og Google Assistant i organisasjonskontekst (nivå 2, bare Android).
        screenCaptureBlocked                    = $true
        # Telefonnumre kan åpnes i hvilken som helst ringeapp (nivå 2).
        dialerRestrictionLevel                  = 'allApps'
        # Lenker åpnes i Microsoft Edge (nivå 2).
        managedBrowserToOpenLinksRequired       = $true
        managedBrowser                          = 'microsoftEdge'
        # Varsler skjuler organisasjonsdata (nivå 2).
        notificationRestriction                 = 'blockOrganizationalData'
        # Kontaktsynk og utskrift er tillatt i nivå 1 og 2.
        contactSyncBlocked                      = $false
        printBlocked                            = $false
        # Godkjente tastatur kreves ikke i nivå 1 og 2 (nivå 3 krever dem).
        keyboardsRestricted                     = $false

        # --- Kryptering (Android) ---------------------------------------------------------
        # Krypter organisasjonsdata i appen ...
        encryptAppData                                  = $true
        # ... også på registrerte enheter med enhetskryptering (nivå 1: «Require»).
        disableAppEncryptionIfDeviceEncryptionIsEnabled = $false

        # --- Tilgangskrav ---------------------------------------------------------------
        pinRequired                          = $true
        pinCharacterSet                      = 'numeric'
        # Strengere enn nivå 1/2: 6 sifre, ingen enkel PIN (som nivå 3).
        minimumPinLength                     = 6
        simplePinBlocked                     = $true
        # Biometri tillates i stedet for PIN, men PIN kreves igjen etter 1440 minutter.
        fingerprintBlocked                   = $false
        biometricAuthenticationBlocked       = $false
        pinRequiredInsteadOfBiometricTimeout = 'PT1440M'
        periodBeforePinReset                 = 'PT0S'
        # Ingen krav om unik PIN mot tidligere PIN-er (nivå 1: 0).
        previousPinBlockCount                = 0
        # App-PIN kreves selv om enheten har kode (nivå 1).
        disableAppPinIfDevicePinIsSet        = $false
        organizationalCredentialsRequired    = $false
        periodOnlineBeforeAccessCheck        = 'PT30M'

        # --- Betinget start: app ------------------------------------------------------------
        maximumPinRetries                    = 5
        appActionIfMaximumPinRetriesExceeded = 'block'
        # Uten nett: blokker etter 12 timer (Intune-standard, strengere enn rammeverkets
        # 7 dager), tøm organisasjonsdata etter 30 dager (nivå 2).
        periodOfflineBeforeAccessCheck       = 'PT720M'
        periodOfflineBeforeWipeIsEnforced    = 'P30D'
        appActionIfUnableToAuthenticateUser  = 'block'

        # --- Betinget start: enhet (Android) -----------------------------------------------
        # Rootede enheter: blokker.
        deviceComplianceRequired                          = $true
        appActionIfDeviceComplianceRequired               = 'block'
        # Play Integrity: grunnleggende integritet og sertifisert enhet, blokker ved feil (nivå 1).
        requiredAndroidSafetyNetDeviceAttestationType     = 'basicIntegrityAndDeviceCertification'
        appActionIfAndroidSafetyNetDeviceAttestationFailed = 'block'
        # Evalueringstype: maskinvarebasert gir sterkere rootdeteksjon (nivå 2). Test først.
        requiredAndroidSafetyNetEvaluationType            = $PlayIntegrityEvaluationType
        # Krev at Google Verify Apps (Play Protect-skanning) er på (nivå 1).
        requiredAndroidSafetyNetAppsVerificationType      = 'enabled'
        appActionIfAndroidSafetyNetAppsVerificationFailed = 'block'
        # Krev enhetslås med minst middels kompleksitet, ellers blokker (nivå 2).
        appActionIfDevicePasscodeComplexityLessThanMedium = 'block'
        minimumRequiredOsVersion                          = $MinimumRequiredOsVersion

        # --- Målapper ---------------------------------------------------------------------
        appGroupType                = $script:EffectiveAppGroupType
        targetedAppManagementLevels = 'unspecified'
    }

    if ($MinimumRequiredPatchVersion) {
        # Eldste sikkerhetsoppdatering før tilgang blokkeres (nivå 2, valgfri her).
        $body.minimumRequiredPatchVersion = $MinimumRequiredPatchVersion
    }
    return $body
}

function Get-TargetAppList {
    <#
    .SYNOPSIS
        Lager listen over managedMobileApp-objekter for selectedPublicApps (Android-pakkenavn).
    #>
    $apps = @()
    foreach ($package in @($PackageIds)) {
        if (-not $package) { continue }
        $apps += @{
            '@odata.type'       = '#microsoft.graph.managedMobileApp'
            mobileAppIdentifier = @{
                '@odata.type' = '#microsoft.graph.androidMobileAppIdentifier'
                packageId     = $package
            }
        }
    }
    return , $apps
}

# -----------------------------------------------------------------------------
# Hovedflyt
# -----------------------------------------------------------------------------
Assert-AppOnlyParameterSet

if ($script:CustomAppIds.Count -gt 0 -and $PSBoundParameters.ContainsKey('AppGroupType')) {
    throw "-$script:CustomAppParamName og -AppGroupType kan ikke brukes sammen. Egne apper krever selectedPublicApps."
}
$script:EffectiveAppGroupType = if ($script:CustomAppIds.Count -gt 0) { 'selectedPublicApps' } else { $AppGroupType }

$scopeLabel = @{ Unmanaged = 'Uadministrerte enheter'; Managed = 'Administrerte enheter'; All = 'Alle enheter' }[$DeviceManagementScope]
if (-not $DisplayName) {
    $DisplayName = "APP - $script:PlatformShortName - Nivå 2 - $scopeLabel"
}

Write-Host "Plattform     : $script:PlatformLabel"
Write-Host "Policy        : $DisplayName"
Write-Host "Omfang        : $DeviceManagementScope ($scopeLabel)"
Write-Host "Målapper      : $script:EffectiveAppGroupType $(if ($script:CustomAppIds.Count -gt 0) { '(' + ($script:CustomAppIds -join ', ') + ')' })"

$scopes = @('DeviceManagementApps.ReadWrite.All')
if ($DeviceManagementScope -ne 'All' -and -not $SkipAssignment) { $scopes += 'DeviceManagementConfiguration.ReadWrite.All' }
if ($UserGroupName) { $scopes += 'Group.Read.All' }

Import-GraphAuthenticationModule
Connect-IntuneGraph -Scopes $scopes

if (-not $SkipAssignment -and -not $UserGroupId -and -not $UserGroupName) {
    throw "Oppgi -UserGroupId eller -UserGroupName, eller bruk -SkipAssignment."
}

# 1. Finn eksisterende policy med samme visningsnavn (ingen duplikater).
Write-Host "Sjekker om policyen allerede finnes..."
$existing = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/$script:PolicyCollection" |
        Where-Object { (Get-Prop $_ 'displayName') -eq $DisplayName })

if ($existing.Count -gt 1) {
    $ids = ($existing | ForEach-Object { Get-Prop $_ 'id' }) -join ', '
    throw "Fant flere $script:PlatformLabel-policyer med navnet '$DisplayName' ($ids). Rydd opp i Intune før du kjører på nytt."
}

$policy = $null
if ($existing.Count -eq 1) {
    $policy = $existing[0]
    Write-Host "Policyen finnes allerede ($(Get-Prop $policy 'id')). Innstillingene blir ikke overskrevet."
}
else {
    $body = New-PolicyBody
    if ($PSCmdlet.ShouldProcess($DisplayName, "Opprett $script:PlatformLabel app-beskyttelsespolicy")) {
        Write-Host "Oppretter policyen..."
        $policy = Invoke-Graph -Method POST -Uri "$script:GraphBeta/deviceAppManagement/$script:PolicyCollection" -Body $body

        # 2. Sett målapper. targetApps er dokumentert på managedAppPolicies.
        $targetBody = @{ apps = (Get-TargetAppList); appGroupType = $script:EffectiveAppGroupType }
        Invoke-Graph -Method POST -Uri "$script:GraphBeta/deviceAppManagement/managedAppPolicies/$(Get-Prop $policy 'id')/targetApps" -Body $targetBody | Out-Null
        Write-Host "Opprettet policyen ($(Get-Prop $policy 'id')) og satte målapper ($script:EffectiveAppGroupType)."
    }
    else {
        Write-Host "WhatIf: ville opprettet policyen '$DisplayName' med disse innstillingene:"
        $body.GetEnumerator() | Where-Object { $_.Key -notlike '@odata*' } | ForEach-Object { Write-Host ("  {0,-42} {1}" -f $_.Key, ($_.Value -join ', ')) }
    }
}

if ($SkipAssignment) {
    Write-Host "Tildeling hoppet over (-SkipAssignment)."
    return $policy
}

# 3. Filter og tildeling.
$groupId = Resolve-EntraGroupId -Id $UserGroupId -Name $UserGroupName
$filterId = $null
$filterType = 'none'
if ($DeviceManagementScope -ne 'All') {
    $filter = Get-OrNewUnmanagedAppFilter
    if ($filter) { $filterId = [string](Get-Prop $filter 'id') }
    $filterType = if ($DeviceManagementScope -eq 'Unmanaged') { 'include' } else { 'exclude' }
}

if (-not $policy) {
    Write-Host "WhatIf: ville tildelt policyen til gruppe $groupId med filter $filterType."
    return
}
if ($DeviceManagementScope -ne 'All' -and -not $filterId) {
    Write-Host "WhatIf: filteret finnes ikke ennå, så tildelingen med filter vises bare som plan."
    return
}

Add-AppProtectionAssignment -PolicyId ([string](Get-Prop $policy 'id')) -GroupId $groupId -FilterId $filterId -FilterType $filterType

Write-Host ""
Write-Host "Merk (Android): Intune Company Portal må være installert på enheten for at policyen skal virke,"
Write-Host "også uten enrollment. Brukerne installerer den fra Google Play; på fully managed installeres den automatisk."
Write-Host "Neste steg: test med en pilotbruker på Android, og vent på at policyen leveres før du slår på Conditional Access."

return $policy

