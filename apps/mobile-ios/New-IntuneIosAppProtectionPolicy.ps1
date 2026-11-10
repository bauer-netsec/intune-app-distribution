#Requires -Version 5.1
# UTF-8 med BOM, slik at æ/ø/å vises riktig også i Windows PowerShell 5.1.
<#
.SYNOPSIS
    Oppretter en iOS/iPadOS app-beskyttelsespolicy (APP/MAM) i Intune med sikre standardvalg.

.DESCRIPTION
    Scriptet oppretter én iOS/iPadOS app-beskyttelsespolicy basert på Microsofts
    rammeverk for databeskyttelse, nivå 2 «Enterprise enhanced» (anbefalt for de fleste
    ansatte), med noen bevisst strengere PIN-valg fra nivå 3. Hvert valg er forklart i
    kommentarene der verdien settes (se New-PolicyBody).

    Policyen finnes bare én gang: hvis en iOS-policy med samme visningsnavn allerede finnes,
    hopper scriptet over oppretting og bruker den eksisterende (ingen duplikater).

    Med eller uten enrollment (MAM-WE):
      App-beskyttelsespolicyer tildeles brukergrupper. Hvilke enheter de treffer, styres
      etter Microsofts anbefaling med et filter for administrerte apper
      (app.deviceManagementType) på tildelingen:

        -DeviceManagementScope Unmanaged  Bare iPhone/iPad uten Intune-MDM (BYOD, MAM-WE).
                                          Standard. Filteret tas med som Include.
        -DeviceManagementScope Managed    Bare Intune-registrerte enheter. Samme filter tas
                                          med som Exclude.
        -DeviceManagementScope All        Alle enheter, uten filter.

      Viktig for iOS: Intune behandler en app som administrert bare når appen får
      app-konfigurasjonsnøklene IntuneMAMUPN og IntuneMAMOID (og IntuneMAMDeviceID for
      tredjeparts- og LOB-apper) via en app-konfigurasjonspolicy for administrerte enheter.
      Uten dem regnes enheten som uadministrert. Intune sender nøklene automatisk til noen
      Microsoft-apper (blant annet Outlook, Teams, Word, Excel, PowerPoint), men ikke til alle.

    iOS-spesifikt (skiller seg fra Android):
      - Ingen Company Portal kreves for APP på iOS. Microsoft Authenticator er megler-appen
        når Conditional Access krever app-beskyttelsespolicy.
      - Kryptering styres med appDataEncryptionType (iOS-databeskyttelsesklasse), ikke
        med encryptAppData som på Android.
      - Face ID/Touch ID styres med faceIdBlocked/fingerprintBlocked.
      - Android-innstillinger som skjermbildeblokkering, Play Integrity og enhetslås finnes
        ikke her. De ligger i New-IntuneAndroidAppProtectionPolicy.ps1.

    Scriptet gjør dette:
      1. Kobler til Graph med minste nødvendige rettigheter.
      2. Finner eller oppretter iOS-policyen (Graph beta, se .NOTES).
      3. Setter målapper (Microsoft-apper eller egne bundle-ID-er).
      4. Finner eller oppretter filteret for uadministrerte iOS-apper når det trengs.
      5. Legger til tildeling til brukergruppen og beholder eksisterende tildelinger.

.PARAMETER DisplayName
    Visningsnavn for policyen. Standard følger konvensjonen
    "APP - iOS - Nivå 2 - <omfang>", for eksempel "APP - iOS - Nivå 2 - Uadministrerte enheter".

.PARAMETER Description
    Beskrivelse som lagres på policyen.

.PARAMETER DeviceManagementScope
    Unmanaged (standard, MAM uten enrollment), Managed (bare MDM-registrerte) eller All.

.PARAMETER UserGroupId
    Objekt-ID for brukergruppen som skal få policyen. APP tildeles brukere, ikke enheter.

.PARAMETER UserGroupName
    Visningsnavn for brukergruppen hvis du ikke har ID. Krever Group.Read.All.

.PARAMETER SkipAssignment
    Opprett eller oppdater policyen uten å tildele den. Nyttig for gjennomgang først.

.PARAMETER AppGroupType
    allMicrosoftApps (standard), allCoreMicrosoftApps eller allApps.
    Ignoreres når -BundleIds brukes.

.PARAMETER BundleIds
    Bestemte iOS-bundle-ID-er, for eksempel egne apper med Intune SDK eller App Wrapping Tool.
    Gir appGroupType selectedPublicApps. Kan ikke kombineres med appgruppene.

.PARAMETER MinimumRequiredOsVersion
    Laveste iOS/iPadOS-versjon før tilgang blokkeres. Standard 18.0 (N-1 i forhold til
    iOS 26 per november 2026). Kontroller mot dagens Apple-versjoner før produksjon.

.PARAMETER MinimumWarningOsVersion
    iOS-versjon under denne gir advarsel. Standard 26.0.

.PARAMETER UnmanagedFilterName
    Navn på filteret for uadministrerte iOS-apper. Gjenbrukes hvis det finnes.

.PARAMETER TenantId
    Tenant-ID. Valgfri ved interaktiv pålogging, påkrevd sammen med sertifikat.

.PARAMETER ClientId
    App-registreringens program-ID ved app-only-pålogging med sertifikat.

.PARAMETER CertificateThumbprint
    Tommelavtrykk for sertifikatet i lokalt sertifikatlager. App-only, uten hemmelighet.

.EXAMPLE
    .\New-IntuneIosAppProtectionPolicy.ps1 -UserGroupName 'Pilot - Mobil APP - Brukere' -WhatIf

.EXAMPLE
    .\New-IntuneIosAppProtectionPolicy.ps1 -UserGroupId '<gruppe-id>' -DeviceManagementScope Unmanaged

.EXAMPLE
    .\New-IntuneIosAppProtectionPolicy.ps1 -UserGroupId '<gruppe-id>' -DeviceManagementScope Managed

.EXAMPLE
    .\New-IntuneIosAppProtectionPolicy.ps1 -TenantId '<tenant>' -ClientId '<app-id>' -CertificateThumbprint '<thumbprint>' -UserGroupId '<gruppe-id>'

.NOTES
    Minste Graph-rettigheter:
      - DeviceManagementApps.ReadWrite.All           (policy, målapper, tildeling)
      - DeviceManagementConfiguration.ReadWrite.All  (filter for administrerte apper; bare ved Unmanaged/Managed)
      - Group.Read.All                               (bare ved -UserGroupName)

    Hvorfor Graph beta:
      Policyen opprettes på /beta/deviceAppManagement/iosManagedAppProtections fordi flere
      av innstillingene i nivå 2 (blant annet notificationRestriction, dialerRestrictionLevel,
      appActionIfUnableToAuthenticateUser, pinRequiredInsteadOfBiometricTimeout og appGroupType)
      bare finnes i beta. Filtere for administrerte apper (assignmentFilterManagementType = apps)
      opprettes også via beta. Microsoft støtter Intune-beta, men den kan endres oftere.
      Tilsvarende cmdlets: New-MgBetaDeviceAppManagementIosManagedAppProtection
      (Microsoft.Graph.Beta) og New-MgDeviceAppManagementIosManagedAppProtection
      (Microsoft.Graph, v1.0 med færre egenskaper). Den utgåtte Microsoft.Graph.Intune-modulen
      brukes ikke.

    Assign-handlingen erstatter alle tildelinger på policyen. Scriptet leser derfor
    eksisterende tildelinger og sender dem med, slik at ingenting forsvinner.

    Kilder (sjekket 10. november 2026):
      https://learn.microsoft.com/en-us/intune/app-management/protection/data-protection-framework
      https://learn.microsoft.com/en-us/intune/app-management/protection/create-policy
      https://learn.microsoft.com/en-us/intune/fundamentals/filters/ref-device-properties
      https://learn.microsoft.com/en-us/graph/api/resources/intune-mam-iosmanagedappprotection?view=graph-rest-beta
      https://learn.microsoft.com/en-us/graph/api/intune-mam-targetedmanagedappprotection-targetapps?view=graph-rest-beta
      https://learn.microsoft.com/en-us/graph/api/intune-mam-targetedmanagedappprotection-assign?view=graph-rest-beta
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ByGroupId')]
param(
    [string]$DisplayName,

    [string]$Description = 'iOS/iPadOS app-beskyttelse etter Microsofts rammeverk nivå 2 (Enterprise enhanced), med PIN fra nivå 3. Opprettet med New-IntuneIosAppProtectionPolicy.ps1.',

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

    [ValidatePattern('^[A-Za-z0-9\.\-]+$')]
    [string[]]$BundleIds,

    [ValidatePattern('^\d+(\.\d+){0,2}$')]
    [string]$MinimumRequiredOsVersion = '18.0',

    [ValidatePattern('^\d+(\.\d+){0,2}$')]
    [string]$MinimumWarningOsVersion = '26.0',

    [string]$UnmanagedFilterName = 'Filter - iOS MAM - Uadministrerte enheter',

    [string]$TenantId,

    [string]$ClientId,

    [string]$CertificateThumbprint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'

# Plattformverdier for iOS. Android-scriptet har egne verdier.
$script:PolicyCollection = 'iosManagedAppProtections'
$script:PolicyODataType = '#microsoft.graph.iosManagedAppProtection'
$script:FilterPlatform = 'iOSMobileApplicationManagement'
$script:PlatformLabel = 'iOS/iPadOS'
$script:PlatformShortName = 'iOS'

# Egne apper (selectedPublicApps) for denne plattformen.
$script:CustomAppIds = @($BundleIds | Where-Object { $_ })
$script:CustomAppParamName = 'BundleIds'

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
# iOS-spesifikke innstillinger
# -----------------------------------------------------------------------------
function New-PolicyBody {
    <#
    .SYNOPSIS
        Bygger policyobjektet med dokumenterte, konservative bedriftsverdier for iOS/iPadOS.
    #>
    $body = [ordered]@{
        '@odata.type' = $script:PolicyODataType
        displayName   = $DisplayName
        description   = $Description

        # --- Dataoverføring (nivå 2) ---------------------------------------------------
        # Ingen sikkerhetskopi av organisasjonsdata til iCloud/iTunes.
        dataBackupBlocked                       = $true
        # Organisasjonsdata kan bare sendes til andre policy-administrerte apper.
        allowedOutboundDataTransferDestinations = 'managedApps'
        # Nivå 2 tillater mottak fra alle apper. Nivå 3 strammer dette inn til managedApps.
        allowedInboundDataTransferSources       = 'allApps'
        # Blokker «Lagre som» utenfor godkjente steder ...
        saveAsBlocked                           = $true
        # ... men tillat OneDrive for Business, SharePoint og bildebiblioteket (nivå 2).
        allowedDataStorageLocations             = @('oneDriveForBusiness', 'sharePoint', 'photoLibrary')
        # Klipp ut/kopier bare mellom administrerte apper, men lim inn fra alle apper.
        allowedOutboundClipboardSharingLevel    = 'managedAppsWithPasteIn'
        # Telefonnumre kan åpnes i hvilken som helst ringeapp (nivå 2).
        dialerRestrictionLevel                  = 'allApps'
        # Lenker fra organisasjonsdata åpnes i Microsoft Edge (nivå 2).
        managedBrowserToOpenLinksRequired       = $true
        managedBrowser                          = 'microsoftEdge'
        # Varsler viser ikke organisasjonsdata på låseskjermen (nivå 2).
        notificationRestriction                 = 'blockOrganizationalData'
        # Kontaktsynk og utskrift er tillatt i nivå 1 og 2. Endre bare ved behov.
        contactSyncBlocked                      = $false
        printBlocked                            = $false
        # Tredjepartstastatur tillates i nivå 2. Nivå 3 blokkerer dem.
        thirdPartyKeyboardsBlocked              = $false

        # --- Kryptering (iOS) -------------------------------------------------------------
        # Sterkeste iOS-databeskyttelsesklasse: data er kryptert når enheten er låst.
        appDataEncryptionType                   = 'whenDeviceLocked'

        # --- Tilgangskrav ---------------------------------------------------------------
        pinRequired                             = $true
        pinCharacterSet                         = 'numeric'
        # Strengere enn nivå 1/2 (4 sifre, enkel PIN tillatt): 6 sifre og ingen enkel PIN,
        # som i nivå 3. Bevisst valg for bedriftsdata.
        minimumPinLength                        = 6
        simplePinBlocked                        = $true
        # Face ID og Touch ID tillates i stedet for PIN ...
        fingerprintBlocked                      = $false
        faceIdBlocked                           = $false
        # ... men PIN kreves igjen etter 1440 minutter (nivå 1).
        pinRequiredInsteadOfBiometricTimeout    = 'PT1440M'
        # Ingen tvungen PIN-bytte etter antall dager (nivå 1).
        periodBeforePinReset                    = 'PT0S'
        # App-PIN kreves selv om enheten har kode (nivå 1). På MDM-enheter med streng
        # enhetskode via samsvarspolicy kan dette vurderes slått av.
        disableAppPinIfDevicePinIsSet           = $false
        # Jobbkonto kreves ikke i tillegg til PIN (nivå 1).
        organizationalCredentialsRequired       = $false
        # Kontroller tilgangskravene på nytt etter 30 minutter inaktivitet (nivå 1).
        periodOnlineBeforeAccessCheck           = 'PT30M'

        # --- Betinget start ---------------------------------------------------------------
        # Maks 5 PIN-forsøk. block er den milde handlingen (ingen tømming).
        maximumPinRetries                       = 5
        appActionIfMaximumPinRetriesExceeded    = 'block'
        # Uten nett: blokker etter 720 minutter (12 timer), tøm organisasjonsdata etter 30 dager.
        # Rammeverket bruker 10080 minutter (7 dager) i nivå 1. 12 timer er strengere og
        # Intunes egen standard. Endre periodOfflineBeforeAccessCheck hvis det blir for strengt.
        periodOfflineBeforeAccessCheck          = 'PT720M'
        periodOfflineBeforeWipeIsEnforced       = 'P30D'
        # Deaktivert eller slettet konto i Entra ID: blokker tilgang (nivå 2).
        appActionIfUnableToAuthenticateUser     = 'block'
        # Jailbrokede enheter: blokker tilgang (nivå 1).
        deviceComplianceRequired                = $true
        appActionIfDeviceComplianceRequired     = 'block'
        # Laveste iOS-versjon (nivå 2: N-1).
        minimumRequiredOsVersion                = $MinimumRequiredOsVersion
        minimumWarningOsVersion                 = $MinimumWarningOsVersion

        # --- Målapper ---------------------------------------------------------------------
        # Settes også med targetApps etter oppretting. targetedAppManagementLevels står som
        # 'unspecified' (alle enhetstyper); omfanget styres med filter på tildelingen, slik
        # Microsoft anbefaler.
        appGroupType                            = $script:EffectiveAppGroupType
        targetedAppManagementLevels             = 'unspecified'
    }
    return $body
}

function Get-TargetAppList {
    <#
    .SYNOPSIS
        Lager listen over managedMobileApp-objekter for selectedPublicApps (iOS-bundle-ID-er).
    #>
    $apps = @()
    foreach ($bundle in @($BundleIds)) {
        if (-not $bundle) { continue }
        $apps += @{
            '@odata.type'       = '#microsoft.graph.managedMobileApp'
            mobileAppIdentifier = @{
                '@odata.type' = '#microsoft.graph.iosMobileAppIdentifier'
                bundleId      = $bundle
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

if ($DeviceManagementScope -ne 'Unmanaged') {
    Write-Host ""
    Write-Host "Merk (iOS): for at Intune skal se appene som administrert på registrerte enheter, må appene"
    Write-Host "få IntuneMAMUPN og IntuneMAMOID (og IntuneMAMDeviceID for tredjeparts-/LOB-apper) via en"
    Write-Host "app-konfigurasjonspolicy for administrerte enheter. Ellers regnes enheten som uadministrert."
}
Write-Host "Neste steg: test med en pilotbruker på iPhone, og vent på at policyen leveres før du slår på Conditional Access."

return $policy

