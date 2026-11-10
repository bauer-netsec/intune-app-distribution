#Requires -Version 5.1
# UTF-8 med BOM, slik at æ/ø/å vises riktig også i Windows PowerShell 5.1.
<#
.SYNOPSIS
    Henter gjeldende status fra Microsoft Intune før en utrulling, og lagrer den som en
    lesbar Markdown-rapport (klar for Confluence).

.DESCRIPTION
    Scriptet er bare lesende. Det endrer ingenting i Intune eller Entra ID.

    Rapporten inneholder:
      0. Funn som bør vurderes før utrulling (utløpte token, apper uten tildeling osv.).
      1. Alle publiserte apper: navn, plattform, type (LOB, Win32, MSIX/APPX, Store, VPP,
         Managed Google Play, webapper osv.), versjon og tildelinger med intent
         (Required/Available/Uninstall) og ev. filter.
      2. Grupper og hvilke apper som er tildelt hver gruppe (omvendt indeks av punkt 1).
      3. Samsvarspolicyer (compliance) med tildelinger og enhetsstatus slik Graph rapporterer
         den (antall per status, og eventuelt enheter som ikke er i samsvar).
      4. Registrering (enrollment), i egne avsnitt for iOS/iPadOS og Android:
           iOS: APNs-sertifikat, ADE-token og ADE-profiler, Apple-brukerinitierte profiler
                (enhetsregistrering, kontobasert brukerregistrering osv.), VPP-token og
                registreringsbegrensninger.
           Android: Managed Google Play-kobling, Android Enterprise-profiler (fully managed,
                dedikert, corporate-owned work profile, AOSP) og begrensninger for personlig
                work profile.
      5. App-beskyttelsespolicyer for iOS og Android hver for seg, med målapper, tildeling,
         filter og om de gjelder med eller uten enrollment.
      6. Kort oversikt over administrerte enheter per operativsystem og samsvarsstatus.

    Feiltoleranse: hvert avsnitt hentes for seg. Mangler en rettighet eller et API svarer
    med feil, skrives feilen inn i rapporten og resten fortsetter.

    Personvern: rapporten tar bare med enhetsnavn og brukernavn for enheter som ikke er i
    samsvar (kan slås av med -IncludeComplianceDeviceDetails:$false). Hemmelige felt som
    registreringstoken, QR-koder, Wi-Fi-passord og VPP-tokenverdier hentes aldri.

.PARAMETER OutputPath
    Sti til rapportfilen. Standard: .\Intune-forutsetningsrapport-<dato>-<tid>.md

.PARAMETER IncludeComplianceDeviceDetails
    Ta med enheter som ikke er i samsvar, per samsvarspolicy. Standard: $true.

.PARAMETER MaxDevicesPerPolicy
    Maks antall enheter som listes per samsvarspolicy. Standard: 25.

.PARAMETER IncludeManagedDeviceSummary
    Ta med antall administrerte enheter per OS (krever DeviceManagementManagedDevices.Read.All).
    Standard: $true.

.PARAMETER NoConsoleOutput
    Ikke skriv hele rapporten til konsollen, bare filstien.

.PARAMETER TenantId
    Tenant-ID. Valgfri ved interaktiv pålogging, påkrevd sammen med sertifikat.

.PARAMETER ClientId
    App-registreringens program-ID ved app-only-pålogging med sertifikat.

.PARAMETER CertificateThumbprint
    Tommelavtrykk for sertifikatet i lokalt sertifikatlager. App-only, uten hemmelighet.

.EXAMPLE
    .\Get-IntunePreDeploymentReport.ps1

.EXAMPLE
    .\Get-IntunePreDeploymentReport.ps1 -OutputPath .\Intune-forutsetningsrapport.md -NoConsoleOutput

.EXAMPLE
    .\Get-IntunePreDeploymentReport.ps1 -TenantId '<tenant>' -ClientId '<app-id>' -CertificateThumbprint '<thumbprint>' -OutputPath C:\Rapporter\intune.md

.NOTES
    Minste Graph-rettigheter (bare lesing, delegert eller app-only):
      - DeviceManagementApps.Read.All            apper, apptildelinger, app-beskyttelse, VPP-token
      - DeviceManagementConfiguration.Read.All   samsvarspolicyer og status, filtre,
                                                 Managed Google Play-kobling, Android Enterprise-profiler
      - DeviceManagementServiceConfig.Read.All   APNs, ADE-token og -profiler, Apple-brukerinitierte
                                                 profiler, registreringsbegrensninger
      - DeviceManagementManagedDevices.Read.All  enhetsoversikt (avsnitt 6; kan slås av)
      - Group.Read.All                           gruppenavn for tildelinger
    Delegert pålogging krever i tillegg en Intune-rolle som får lese dette (for eksempel Read Only Operator).

    Graph-versjoner: v1.0 brukes der ressursen finnes (samsvar, APNs, VPP, enheter,
    grupper). Beta brukes der v1.0 mangler ressursen eller feltene: appliste og
    apptildelinger (androidManagedStoreApp er bare dokumentert i beta), ADE-token/-profiler, Apple-brukerinitierte profiler, Android Enterprise-profiler,
    Managed Google Play-kobling, filtre, Android work profile-begrensning og
    app-beskyttelsesfeltene appGroupType/targetedAppManagementLevels.

    Kjente begrensninger (ikke gjettet):
      - Samsvarspolicyer laget i Settings catalog (for eksempel Linux) ligger ikke i
        deviceCompliancePolicies og vises ikke.
      - ADE-policyer laget i den nye opplevelsen «Enrollment policies» skal ligge under
        samme ADE-token, men Microsoft har ikke dokumentert om alle nye felt vises i
        enrollmentProfiles. Sammenlign med admin-senteret første gang.
      - Personlig Android work profile har ingen egen profil i Graph. Det styres av
        Managed Google Play-koblingen og registreringsbegrensningene, som rapporten viser.

    Kilder (sjekket 10. november 2026):
      https://learn.microsoft.com/en-us/graph/api/intune-apps-mobileapp-list?view=graph-rest-1.0
      https://learn.microsoft.com/en-us/graph/api/resources/intune-deviceconfig-devicecompliancedeviceoverview?view=graph-rest-1.0
      https://learn.microsoft.com/en-us/graph/api/intune-enrollment-enrollmentprofile-list?view=graph-rest-beta
      https://learn.microsoft.com/en-us/graph/api/intune-enrollment-appleuserinitiatedenrollmentprofile-list?view=graph-rest-beta
      https://learn.microsoft.com/en-us/graph/api/intune-androidforwork-androiddeviceownerenrollmentprofile-list?view=graph-rest-beta
      https://learn.microsoft.com/en-us/graph/api/intune-mam-iosmanagedappprotection-list?view=graph-rest-1.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$OutputPath,

    [bool]$IncludeComplianceDeviceDetails = $true,

    [ValidateRange(1, 1000)]
    [int]$MaxDevicesPerPolicy = 25,

    [bool]$IncludeManagedDeviceSummary = $true,

    [switch]$NoConsoleOutput,

    [string]$TenantId,

    [string]$ClientId,

    [string]$CertificateThumbprint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'

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
# Tid i Europe/Oslo
# -----------------------------------------------------------------------------
function Get-OsloTimeZone {
    # IANA-navn virker i PowerShell 7 og på Linux/macOS; Windows-navnet i Windows PowerShell 5.1.
    foreach ($id in @('Europe/Oslo', 'W. Europe Standard Time')) {
        try { return [TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { continue }
    }
    return [TimeZoneInfo]::Local
}
$script:OsloZone = Get-OsloTimeZone

function Format-OsloTime {
    param($Value, [switch]$WithZone)
    $dto = $null
    try { $dto = ConvertTo-DateTimeOffsetValue $Value } catch { return [string]$Value }
    if ($null -eq $dto) { return '–' }
    $local = [TimeZoneInfo]::ConvertTime($dto, $script:OsloZone)
    $text = $local.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)
    if ($WithZone) {
        $offset = $local.Offset
        $sign = if ($offset -lt [TimeSpan]::Zero) { '-' } else { '+' }
        $text += (" (Europe/Oslo, UTC{0}{1:hh\:mm})" -f $sign, $offset.Duration())
    }
    return $text
}

function Get-DaysUntil {
    param($Value)
    $dto = ConvertTo-DateTimeOffsetValue $Value
    if ($null -eq $dto) { return $null }
    return [int][math]::Floor(($dto - [DateTimeOffset]::UtcNow).TotalDays)
}

# -----------------------------------------------------------------------------
# Markdown-bygging
# -----------------------------------------------------------------------------
$script:Body = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.Generic.List[string]

function Add-Line { param([string]$Text = '') $script:Body.Add($Text) }

function Add-Finding { param([string]$Text) $script:Findings.Add($Text) }

function ConvertTo-MdCell {
    param($Value)
    if ($null -eq $Value) { return '–' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '–' }
    return ($text -replace '\r?\n', ' ' -replace '\|', '\|')
}

function Add-Table {
    <#
    .SYNOPSIS
        Skriver en Markdown-tabell. Rader er lister med celleverdier i samme rekkefølge som kolonnene.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Headers, [object[]]$Rows)
    if (-not $Rows -or @($Rows).Count -eq 0) {
        Add-Line '_Ingen funnet._'
        Add-Line
        return
    }
    Add-Line ('| ' + ($Headers -join ' | ') + ' |')
    Add-Line ('|' + (($Headers | ForEach-Object { ' --- ' }) -join '|') + '|')
    foreach ($row in $Rows) {
        $cells = @($row | ForEach-Object { ConvertTo-MdCell $_ })
        Add-Line ('| ' + ($cells -join ' | ') + ' |')
    }
    Add-Line
}

function Invoke-ReportSection {
    <#
    .SYNOPSIS
        Kjører ett avsnitt. Feil (for eksempel manglende rettighet) skrives i rapporten i stedet for å stoppe alt.
    #>
    param([Parameter(Mandatory = $true)][string]$Title, [Parameter(Mandatory = $true)][scriptblock]$Script, [int]$Level = 2)
    Write-Host "Henter: $Title"
    Add-Line ('#' * $Level + ' ' + $Title)
    Add-Line
    try {
        & $Script
    }
    catch {
        $message = $_.Exception.Message -replace '\r?\n', ' '
        Add-Line "> Kunne ikke hente dette avsnittet: $message"
        Add-Line
        Add-Finding "Avsnittet «$Title» kunne ikke hentes ($message). Sjekk rettigheter og rolle."
        Write-Warning "$Title`: $message"
    }
}

# -----------------------------------------------------------------------------
# Oppslag: grupper, filtre, tildelinger, apptyper
# -----------------------------------------------------------------------------
$script:GroupCache = @{}
function Get-GroupInfo {
    param([Parameter(Mandatory = $true)][string]$Id)
    if ($script:GroupCache.ContainsKey($Id)) { return $script:GroupCache[$Id] }
    $info = @{ Name = "Ukjent eller slettet gruppe ($Id)"; Kind = '–' }
    try {
        $g = Invoke-Graph -Uri "$script:GraphV1/groups/$Id`?`$select=id,displayName,groupTypes,membershipRule"
        $types = @(Get-Prop $g 'groupTypes')
        $rule = [string](Get-Prop $g 'membershipRule')
        $kind = 'Tildelt'
        if ($types -contains 'DynamicMembership') {
            $kind = if ($rule -match '\bdevice\.') { 'Dynamisk (enheter)' } elseif ($rule -match '\buser\.') { 'Dynamisk (brukere)' } else { 'Dynamisk' }
        }
        $info = @{ Name = [string](Get-Prop $g 'displayName'); Kind = $kind }
    }
    catch { Write-Verbose "Fant ikke gruppen $Id (slettet eller manglende rettighet)." }
    $script:GroupCache[$Id] = $info
    return $info
}

$script:FilterCache = $null
function Get-FilterInfo {
    param([string]$Id)
    if (-not $Id -or $Id -eq '00000000-0000-0000-0000-000000000000') { return $null }
    if ($null -eq $script:FilterCache) {
        $script:FilterCache = @{}
        try {
            foreach ($f in @(Get-GraphCollection -Uri "$script:GraphBeta/deviceManagement/assignmentFilters")) {
                $script:FilterCache[[string](Get-Prop $f 'id')] = @{ Name = [string](Get-Prop $f 'displayName'); Rule = [string](Get-Prop $f 'rule'); Platform = [string](Get-Prop $f 'platform') }
            }
        }
        catch { Write-Warning "Kunne ikke lese filtre: $($_.Exception.Message)" }
    }
    if ($script:FilterCache.ContainsKey($Id)) { return $script:FilterCache[$Id] }
    return @{ Name = "Ukjent filter ($Id)"; Rule = ''; Platform = '' }
}

function Get-TargetInfo {
    <#
    .SYNOPSIS
        Gjør et tildelingsmål om til en nøkkel (for omvendt indeks) og en lesbar tekst.
    #>
    param($Target)
    $type = [string](Get-Prop $Target '@odata.type')
    $groupId = [string](Get-Prop $Target 'groupId')
    $key = $type; $name = $type; $kind = '–'; $excluded = $false
    switch ($type) {
        '#microsoft.graph.groupAssignmentTarget' { $gi = Get-GroupInfo -Id $groupId; $key = $groupId; $name = $gi.Name; $kind = $gi.Kind }
        '#microsoft.graph.exclusionGroupAssignmentTarget' { $gi = Get-GroupInfo -Id $groupId; $key = $groupId; $name = $gi.Name; $kind = $gi.Kind; $excluded = $true }
        '#microsoft.graph.allDevicesAssignmentTarget' { $key = 'alle-enheter'; $name = 'Alle enheter'; $kind = 'Innebygd' }
        '#microsoft.graph.allLicensedUsersAssignmentTarget' { $key = 'alle-brukere'; $name = 'Alle brukere'; $kind = 'Innebygd' }
    }
    $filterText = ''
    $filterType = [string](Get-Prop $Target 'deviceAndAppManagementAssignmentFilterType')
    $filter = Get-FilterInfo -Id ([string](Get-Prop $Target 'deviceAndAppManagementAssignmentFilterId'))
    if ($filter -and $filterType -and $filterType -ne 'none') { $filterText = " [filter $filterType`: $($filter.Name)]" }
    $label = $name + $(if ($excluded) { ' [ekskludert]' } else { '' }) + $filterText
    return @{ Key = $key; Name = $name; Kind = $kind; Label = $label; Excluded = $excluded; Filter = $filter; FilterType = $filterType }
}

$script:AppTypeMap = @{
    'win32LobApp'                   = @('Windows', 'Win32 (.intunewin)')
    'windowsUniversalAppX'          = @('Windows', 'LOB MSIX/APPX')
    'windowsMobileMSI'              = @('Windows', 'LOB MSI')
    'winGetApp'                     = @('Windows', 'Microsoft Store (ny)')
    'microsoftStoreForBusinessApp'  = @('Windows', 'Microsoft Store for Business (utgått)')
    'windowsStoreApp'               = @('Windows', 'Microsoft Store-lenke')
    'officeSuiteApp'                = @('Windows', 'Microsoft 365-apper')
    'windowsMicrosoftEdgeApp'       = @('Windows', 'Microsoft Edge')
    'windowsWebApp'                 = @('Windows', 'Nettkobling')
    'windowsAppX'                   = @('Windows', 'LOB APPX (eldre)')
    'webApp'                        = @('Alle', 'Nettkobling')
    'iosStoreApp'                   = @('iOS/iPadOS', 'App Store')
    'iosVppApp'                     = @('iOS/iPadOS', 'VPP (Apple Business)')
    'iosLobApp'                     = @('iOS/iPadOS', 'LOB (.ipa)')
    'iosiPadOSWebClip'              = @('iOS/iPadOS', 'Webklipp')
    'managedIOSStoreApp'            = @('iOS/iPadOS', 'App Store for app-beskyttelse (MAM)')
    'managedIOSLobApp'              = @('iOS/iPadOS', 'LOB for app-beskyttelse (MAM)')
    'androidManagedStoreApp'        = @('Android', 'Managed Google Play')
    'androidManagedStoreWebApp'     = @('Android', 'Managed Google Play-nettapp')
    'androidLobApp'                 = @('Android', 'LOB (.apk)')
    'androidStoreApp'               = @('Android', 'Google Play-lenke (ikke Android Enterprise)')
    'managedAndroidStoreApp'        = @('Android', 'Google Play for app-beskyttelse (MAM)')
    'managedAndroidLobApp'          = @('Android', 'LOB for app-beskyttelse (MAM)')
    'androidForWorkApp'             = @('Android', 'Android for Work (eldre)')
    'macOSLobApp'                   = @('macOS', 'LOB (.pkg)')
    'macOSPkgApp'                   = @('macOS', 'PKG')
    'macOSDmgApp'                   = @('macOS', 'DMG')
    'macOsVppApp'                   = @('macOS', 'VPP (Apple Business)')
    'macOSMicrosoftEdgeApp'         = @('macOS', 'Microsoft Edge')
    'macOSMicrosoftDefenderApp'     = @('macOS', 'Microsoft Defender')
    'macOSOfficeSuiteApp'           = @('macOS', 'Microsoft 365-apper')
    'macOSWebClip'                  = @('macOS', 'Webklipp')
}

function Get-AppTypeInfo {
    param([string]$ODataType)
    $short = $ODataType -replace '^#microsoft\.graph\.', ''
    if ($script:AppTypeMap.ContainsKey($short)) { return $script:AppTypeMap[$short] }
    $platform = if ($short -match '(?i)^(managed)?ios') { 'iOS/iPadOS' } elseif ($short -match '(?i)android') { 'Android' } elseif ($short -match '(?i)macos') { 'macOS' } elseif ($short -match '(?i)windows|win32') { 'Windows' } else { 'Annet' }
    return @($platform, $short)
}

function Get-AppVersion {
    <#
    .SYNOPSIS
        Finner versjon på tvers av apptyper. Feltnavnet varierer, og noen typer (Store, VPP, web) har ingen versjon.
    #>
    param($App)
    foreach ($field in @('displayVersion', 'identityVersion', 'productVersion', 'version', 'bundleVersion')) {
        $v = Get-Prop $App $field
        if ($v) { return [string]$v }
    }
    $number = Get-Prop $App 'versionNumber'
    if ($number) {
        $build = Get-Prop $App 'buildNumber'
        return $(if ($build) { "$number (build $build)" } else { [string]$number })
    }
    $name = Get-Prop $App 'versionName'
    if ($name) {
        $code = Get-Prop $App 'versionCode'
        return $(if ($code) { "$name (kode $code)" } else { [string]$name })
    }
    return '–'
}

$script:IntentLabel = @{ required = 'Required'; available = 'Available'; uninstall = 'Uninstall'; availableWithoutEnrollment = 'Available uten enrollment' }

# Fylles i avsnitt 1 og brukes i avsnitt 2.
$script:GroupIndex = @{}

# -----------------------------------------------------------------------------
# Avsnitt
# -----------------------------------------------------------------------------
function Write-AppsSection {
    $apps = @()
    $expanded = $true
    try {
        $apps = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/mobileApps?`$expand=assignments")
    }
    catch {
        # Ikke alle miljøer godtar $expand her. Da hentes tildelinger per app.
        $expanded = $false
        $apps = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/mobileApps")
    }

    $rows = @()
    $unassigned = 0
    $countByPlatform = @{}
    foreach ($app in ($apps | Sort-Object { (Get-AppTypeInfo ([string](Get-Prop $_ '@odata.type')))[0] }, { [string](Get-Prop $_ 'displayName') })) {
        $id = [string](Get-Prop $app 'id')
        $typeInfo = Get-AppTypeInfo ([string](Get-Prop $app '@odata.type'))
        $assignments = if ($expanded -and $null -ne (Get-Prop $app 'assignments')) { @(Get-Prop $app 'assignments') } else { @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/mobileApps/$id/assignments") }

        $labels = @()
        foreach ($a in $assignments) {
            $intent = [string](Get-Prop $a 'intent')
            $intentText = if ($script:IntentLabel.ContainsKey($intent)) { $script:IntentLabel[$intent] } else { $intent }
            $t = Get-TargetInfo -Target (Get-Prop $a 'target')
            $labels += "$intentText`: $($t.Label)"
            if (-not $script:GroupIndex.ContainsKey($t.Key)) {
                $script:GroupIndex[$t.Key] = @{ Name = $t.Name; Kind = $t.Kind; Items = New-Object System.Collections.Generic.List[string] }
            }
            $script:GroupIndex[$t.Key].Items.Add(("{0} ({1}, {2}: {3}){4}" -f (Get-Prop $app 'displayName'), $typeInfo[0], $typeInfo[1], $intentText, $(if ($t.Excluded) { ' [ekskludert]' } else { '' })))
        }
        if ($labels.Count -eq 0) { $unassigned++ }
        if (-not $countByPlatform.ContainsKey($typeInfo[0])) { $countByPlatform[$typeInfo[0]] = 0 }
        $countByPlatform[$typeInfo[0]]++

        $rows += , @(
            (Get-Prop $app 'displayName'),
            $typeInfo[0],
            $typeInfo[1],
            (Get-AppVersion $app),
            (Get-Prop $app 'publishingState'),
            $(if ($labels.Count) { $labels -join '; ' } else { 'Ikke tildelt' })
        )
    }

    $summary = ($countByPlatform.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name): $($_.Value)" }) -join ', '
    Add-Line "Totalt $($apps.Count) apper ($summary). $unassigned er ikke tildelt."
    Add-Line
    Add-Table -Headers @('App', 'Plattform', 'Type', 'Versjon', 'Publisering', 'Tildelinger (intent: mål)') -Rows $rows
    if ($unassigned -gt 0) { Add-Finding "$unassigned apper er publisert uten tildeling. Rydd eller tildel før utrulling, så Company Portal og rapporter blir oversiktlige." }
}

function Write-GroupIndexSection {
    Add-Line 'Omvendt indeks av appavsnittet: hvilke apper hver gruppe eller innebygd mål får.'
    Add-Line
    $rows = @()
    foreach ($entry in ($script:GroupIndex.GetEnumerator() | Sort-Object { $_.Value.Name })) {
        $rows += , @($entry.Value.Name, $entry.Value.Kind, $entry.Value.Items.Count, ($entry.Value.Items -join '; '))
    }
    Add-Table -Headers @('Gruppe / mål', 'Medlemskap', 'Antall apper', 'Apper (plattform, type: intent)') -Rows $rows
    Add-Line '_«Dynamisk (enheter)» betyr at medlemsregelen bruker device.-egenskaper. Tildelte grupper kan inneholde både brukere og enheter; sjekk medlemmene i Entra ID._'
    Add-Line
}

function Get-CompliancePlatform {
    param([string]$ODataType)
    switch -Regex ($ODataType) {
        'androidWorkProfile' { return 'Android Enterprise (personlig work profile)' }
        'androidDeviceOwner' { return 'Android Enterprise (fully managed, dedikert, COPE)' }
        'aosp' { return 'Android (AOSP)' }
        'androidCompliance' { return 'Android device administrator (utgått på GMS)' }
        'ios' { return 'iOS/iPadOS' }
        'macOS' { return 'macOS' }
        'windows' { return 'Windows' }
        default { return ($ODataType -replace '^#microsoft\.graph\.', '') }
    }
}

function Write-ComplianceSection {
    $policies = @(Get-GraphCollection -Uri "$script:GraphV1/deviceManagement/deviceCompliancePolicies")
    Add-Line "Totalt $($policies.Count) samsvarspolicyer. Tallene er Intunes egen statusoversikt (deviceStatusOverview) og kan henge noe etter."
    Add-Line
    $rows = @()
    $details = @()
    foreach ($p in ($policies | Sort-Object { Get-CompliancePlatform ([string](Get-Prop $_ '@odata.type')) }, { [string](Get-Prop $_ 'displayName') })) {
        $id = [string](Get-Prop $p 'id')
        $name = [string](Get-Prop $p 'displayName')
        $assignments = @(Get-GraphCollection -Uri "$script:GraphV1/deviceManagement/deviceCompliancePolicies/$id/assignments")
        $targets = @($assignments | ForEach-Object { (Get-TargetInfo -Target (Get-Prop $_ 'target')).Label })
        if ($targets.Count -eq 0) { Add-Finding "Samsvarspolicyen «$name» er ikke tildelt." }

        $o = $null
        try { $o = Invoke-Graph -Uri "$script:GraphV1/deviceManagement/deviceCompliancePolicies/$id/deviceStatusOverview" } catch { $o = $null }
        $rows += , @(
            $name,
            (Get-CompliancePlatform ([string](Get-Prop $p '@odata.type'))),
            $(if ($targets.Count) { $targets -join '; ' } else { 'Ikke tildelt' }),
            (Get-Prop $o 'successCount'), (Get-Prop $o 'failedCount'), (Get-Prop $o 'errorCount'),
            (Get-Prop $o 'pendingCount'), (Get-Prop $o 'notApplicableCount'),
            $(if ($o) { Format-OsloTime (Get-Prop $o 'lastUpdateDateTime') } else { 'Ikke tilgjengelig' })
        )

        if ($IncludeComplianceDeviceDetails) {
            $statuses = @(Get-GraphCollection -Uri "$script:GraphV1/deviceManagement/deviceCompliancePolicies/$id/deviceStatuses" |
                    Where-Object { (Get-Prop $_ 'status') -in @('nonCompliant', 'error', 'conflict') })
            if ($statuses.Count -gt 0) {
                $details += @{ Policy = $name; Total = $statuses.Count; Items = @($statuses | Select-Object -First $MaxDevicesPerPolicy) }
            }
        }
    }
    Add-Table -Headers @('Policy', 'Plattform', 'Tildelt til', 'I samsvar', 'Ikke i samsvar', 'Feil', 'Venter', 'Ikke aktuelt', 'Sist oppdatert (Oslo)') -Rows $rows

    if ($IncludeComplianceDeviceDetails) {
        Add-Line '### Enheter som ikke er i samsvar, har feil eller konflikt'
        Add-Line
        if ($details.Count -eq 0) { Add-Line '_Ingen._'; Add-Line }
        foreach ($d in $details) {
            Add-Line "**$($d.Policy)** ($($d.Total) enheter$(if ($d.Total -gt $MaxDevicesPerPolicy) { ", viser $MaxDevicesPerPolicy" }))"
            Add-Line
            $drows = @($d.Items | ForEach-Object { , @((Get-Prop $_ 'deviceDisplayName'), (Get-Prop $_ 'userPrincipalName'), (Get-Prop $_ 'deviceModel'), (Get-Prop $_ 'status'), (Format-OsloTime (Get-Prop $_ 'lastReportedDateTime'))) })
            Add-Table -Headers @('Enhet', 'Bruker', 'Modell', 'Status', 'Sist rapportert (Oslo)') -Rows $drows
        }
    }
}

function Get-RestrictionRows {
    <#
    .SYNOPSIS
        Leser registreringsbegrensninger for valgte plattformer, både standardkonfigurasjonen og egne per plattform.
    #>
    param([Parameter(Mandatory = $true)][hashtable]$Platforms)
    $rows = @()
    $configs = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceManagement/deviceEnrollmentConfigurations")
    foreach ($c in $configs) {
        $type = [string](Get-Prop $c '@odata.type')
        $name = Get-Prop $c 'displayName'
        $priority = Get-Prop $c 'priority'
        if ($type -eq '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration') {
            foreach ($property in $Platforms.Keys) {
                $r = Get-Prop $c $property
                if ($null -ne $r) { $rows += , @($name, $priority, $Platforms[$property], (Get-Prop $r 'platformBlocked'), (Get-Prop $r 'personalDeviceEnrollmentBlocked'), (Get-Prop $r 'osMinimumVersion'), (Get-Prop $r 'osMaximumVersion')) }
            }
        }
        elseif ($type -eq '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration') {
            $platformType = [string](Get-Prop $c 'platformType')
            $key = "$($platformType)Restriction"
            if ($Platforms.ContainsKey($key)) {
                $r = Get-Prop $c 'platformRestriction'
                $rows += , @($name, $priority, $Platforms[$key], (Get-Prop $r 'platformBlocked'), (Get-Prop $r 'personalDeviceEnrollmentBlocked'), (Get-Prop $r 'osMinimumVersion'), (Get-Prop $r 'osMaximumVersion'))
            }
        }
    }
    return , $rows
}

$script:AppleEnrollmentTypeLabel = @{
    device                      = 'Enhetsregistrering (Company Portal)'
    user                        = 'Brukerregistrering med Company Portal (ikke for nye registreringer)'
    accountDrivenUserEnrollment = 'Kontobasert brukerregistrering (Apple User Enrollment)'
    webDeviceEnrollment         = 'Nettbasert enhetsregistrering'
    unknown                     = 'Ukjent'
}

function Write-IosEnrollmentSection {
    # APNs
    Add-Line '#### Apple MDM Push-sertifikat (APNs)'
    Add-Line
    $cert = $null
    try { $cert = Invoke-Graph -Uri "$script:GraphV1/deviceManagement/applePushNotificationCertificate?`$select=appleIdentifier,expirationDateTime,lastModifiedDateTime" } catch { $cert = $null }
    if (-not $cert -or -not (Get-Prop $cert 'expirationDateTime')) {
        Add-Line 'APNs-sertifikat er **ikke** konfigurert. Ingen iPhone/iPad kan registreres før det er lastet opp.'
        Add-Finding 'APNs-sertifikat mangler. iOS-registrering og -appdistribusjon virker ikke.'
    }
    else {
        $days = Get-DaysUntil (Get-Prop $cert 'expirationDateTime')
        Add-Table -Headers @('Apple-konto', 'Utløper (Oslo)', 'Dager igjen') -Rows @(, @((Get-Prop $cert 'appleIdentifier'), (Format-OsloTime (Get-Prop $cert 'expirationDateTime')), $days))
        if ($days -lt 0) { Add-Finding 'APNs-sertifikatet er utløpt. Forny med samme Apple-konto.' }
        elseif ($days -lt 30) { Add-Finding "APNs-sertifikatet utløper om $days dager." }
    }
    Add-Line

    # ADE-token og profiler
    Add-Line '#### Automatisert enhetsregistrering (ADE, Apple Business)'
    Add-Line
    $tokens = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceManagement/depOnboardingSettings")
    $tokenRows = @()
    $profileRows = @()
    foreach ($t in $tokens) {
        $days = Get-DaysUntil (Get-Prop $t 'tokenExpirationDateTime')
        $tokenRows += , @((Get-Prop $t 'tokenName'), (Get-Prop $t 'appleIdentifier'), (Format-OsloTime (Get-Prop $t 'tokenExpirationDateTime')), $days, (Format-OsloTime (Get-Prop $t 'lastSuccessfulSyncDateTime')), (Get-Prop $t 'syncedDeviceCount'))
        if ($null -ne $days -and $days -lt 30) { Add-Finding "ADE-tokenet «$(Get-Prop $t 'tokenName')» utløper om $days dager." }
        foreach ($p in @(Get-GraphCollection -Uri "$script:GraphBeta/deviceManagement/depOnboardingSettings/$(Get-Prop $t 'id')/enrollmentProfiles")) {
            $ptype = ([string](Get-Prop $p '@odata.type')) -replace '^#microsoft\.graph\.', ''
            if ($ptype -match '(?i)macos') { continue }
            $profileRows += , @((Get-Prop $t 'tokenName'), (Get-Prop $p 'displayName'), $ptype, (Get-Prop $p 'isDefault'), (Get-Prop $p 'requiresUserAuthentication'), (Get-Prop $p 'supervisedModeEnabled'), (Get-Prop $p 'isMandatory'), (Get-Prop $p 'enableAuthenticationViaCompanyPortal'))
        }
    }
    Add-Table -Headers @('Token', 'Apple-konto', 'Utløper (Oslo)', 'Dager igjen', 'Siste synk (Oslo)', 'Synkede enheter') -Rows $tokenRows
    Add-Line '**ADE-profiler (iOS/iPadOS)** — kolonnene viser Graph-feltene direkte:'
    Add-Line
    Add-Table -Headers @('Token', 'Profil', 'Type', 'Standard (isDefault)', 'Brukeraffinitet (requiresUserAuthentication)', 'Overvåket (supervisedModeEnabled)', 'isMandatory', 'enableAuthenticationViaCompanyPortal') -Rows $profileRows

    # Apple-brukerinitierte profiler
    Add-Line '#### Brukerinitiert registrering (enhetsregistrering og Apple User Enrollment)'
    Add-Line
    $uRows = @()
    foreach ($p in @(Get-GraphCollection -Uri "$script:GraphBeta/deviceManagement/appleUserInitiatedEnrollmentProfiles")) {
        if ((Get-Prop $p 'platform') -and (Get-Prop $p 'platform') -ne 'iOS') { continue }
        $default = [string](Get-Prop $p 'defaultEnrollmentType')
        $options = @(Get-Prop $p 'availableEnrollmentTypeOptions' | Where-Object { $_ } | ForEach-Object { "$(Get-Prop $_ 'ownerType'): $(Get-Prop $_ 'enrollmentType')" }) -join '; '
        $uRows += , @((Get-Prop $p 'displayName'), (Get-Prop $p 'priority'), $(if ($script:AppleEnrollmentTypeLabel.ContainsKey($default)) { $script:AppleEnrollmentTypeLabel[$default] } else { $default }), $options)
    }
    Add-Table -Headers @('Profil', 'Prioritet', 'Standard registreringstype', 'Valg for brukeren (eier: type)') -Rows $uRows

    # VPP
    Add-Line '#### Apple VPP-/plasseringstoken (appdistribusjon)'
    Add-Line
    $vRows = @()
    foreach ($v in @(Get-GraphCollection -Uri "$script:GraphV1/deviceAppManagement/vppTokens?`$select=id,organizationName,state,expirationDateTime,lastSyncDateTime,lastSyncStatus,automaticallyUpdateApps,countryOrRegion")) {
        $days = Get-DaysUntil (Get-Prop $v 'expirationDateTime')
        $vRows += , @((Get-Prop $v 'organizationName'), (Get-Prop $v 'state'), (Format-OsloTime (Get-Prop $v 'expirationDateTime')), $days, (Format-OsloTime (Get-Prop $v 'lastSyncDateTime')), (Get-Prop $v 'lastSyncStatus'), (Get-Prop $v 'automaticallyUpdateApps'), (Get-Prop $v 'countryOrRegion'))
        if ((Get-Prop $v 'state') -ne 'valid') { Add-Finding "VPP-tokenet «$(Get-Prop $v 'organizationName')» har status $(Get-Prop $v 'state')." }
        elseif ($null -ne $days -and $days -lt 30) { Add-Finding "VPP-tokenet «$(Get-Prop $v 'organizationName')» utløper om $days dager." }
    }
    Add-Table -Headers @('Organisasjon', 'Status', 'Utløper (Oslo)', 'Dager igjen', 'Siste synk (Oslo)', 'Synkstatus', 'Auto-oppdater apper', 'Land') -Rows $vRows

    Add-Line '#### Registreringsbegrensninger (iOS/iPadOS)'
    Add-Line
    Add-Table -Headers @('Konfigurasjon', 'Prioritet', 'Plattform', 'Plattform blokkert', 'Personlige blokkert', 'Min OS', 'Maks OS') -Rows (Get-RestrictionRows -Platforms @{ iosRestriction = 'iOS/iPadOS' })
}

$script:AndroidModeLabel = @{
    corporateOwnedDedicatedDevice          = 'Dedikert enhet (COSU)'
    corporateOwnedFullyManaged             = 'Fully managed (COBO)'
    corporateOwnedWorkProfile              = 'Corporate-owned work profile (COPE)'
    corporateOwnedAOSPUserlessDevice       = 'AOSP uten bruker'
    corporateOwnedAOSPUserAssociatedDevice = 'AOSP med bruker'
}
$script:AndroidTokenLabel = @{
    default                                            = 'Standard'
    corporateOwnedDedicatedDeviceWithAzureADSharedMode = 'Dedikert med Entra delt modus'
    deviceStaging                                      = 'Forhåndsklargjøring (staging)'
}

function Write-AndroidEnrollmentSection {
    Add-Line '#### Managed Google Play-kobling'
    Add-Line
    $s = Invoke-Graph -Uri "$script:GraphBeta/deviceManagement/androidManagedStoreAccountEnterpriseSettings?`$select=bindStatus,managedGooglePlayEnterpriseType,ownerOrganizationName,lastAppSyncDateTime,lastAppSyncStatus,enrollmentTarget,deviceOwnerManagementEnabled"
    $bind = [string](Get-Prop $s 'bindStatus')
    Add-Table -Headers @('Status (bindStatus)', 'Type', 'Organisasjon', 'Siste appsynk (Oslo)', 'Synkstatus', 'Hvem kan registrere work profile (enrollmentTarget)') -Rows @(, @($bind, (Get-Prop $s 'managedGooglePlayEnterpriseType'), (Get-Prop $s 'ownerOrganizationName'), (Format-OsloTime (Get-Prop $s 'lastAppSyncDateTime')), (Get-Prop $s 'lastAppSyncStatus'), (Get-Prop $s 'enrollmentTarget')))
    if ($bind -notin @('bound', 'boundAndValidated')) { Add-Finding 'Managed Google Play er ikke koblet. Android Enterprise-registrering og Managed Google Play-apper virker ikke.' }

    Add-Line '#### Android Enterprise-profiler for firmaeide enheter'
    Add-Line
    # Bevisst $select: tokenverdi, QR-kode og Wi-Fi-passord skal ikke inn i rapporten.
    $rows = @()
    foreach ($p in @(Get-GraphCollection -Uri "$script:GraphBeta/deviceManagement/androidDeviceOwnerEnrollmentProfiles?`$select=id,displayName,enrollmentMode,enrollmentTokenType,tokenExpirationDateTime,enrolledDeviceCount")) {
        $mode = [string](Get-Prop $p 'enrollmentMode')
        $tokenType = [string](Get-Prop $p 'enrollmentTokenType')
        $days = Get-DaysUntil (Get-Prop $p 'tokenExpirationDateTime')
        if ($null -ne $days -and $days -lt 0) { Add-Finding "Registreringstokenet for Android-profilen «$(Get-Prop $p 'displayName')» er utløpt. Nye enheter kan ikke registreres med profilen før tokenet fornyes." }
        $rows += , @((Get-Prop $p 'displayName'), $(if ($script:AndroidModeLabel.ContainsKey($mode)) { $script:AndroidModeLabel[$mode] } else { $mode }), $(if ($script:AndroidTokenLabel.ContainsKey($tokenType)) { $script:AndroidTokenLabel[$tokenType] } else { $tokenType }), (Format-OsloTime (Get-Prop $p 'tokenExpirationDateTime')), $(if ($null -eq $days) { '–' } elseif ($days -lt 0) { 'Utløpt' } else { $days }), (Get-Prop $p 'enrolledDeviceCount'))
    }
    Add-Table -Headers @('Profil', 'Registreringstype', 'Tokentype', 'Token utløper (Oslo)', 'Dager igjen', 'Registrerte enheter') -Rows $rows

    Add-Line '#### Personlige enheter med work profile (BYOD) og registreringsbegrensninger'
    Add-Line
    Add-Line 'Personlig work profile har ingen egen profil i Graph. Den styres av Managed Google Play-koblingen og begrensningene under. Android device administrator er utgått på enheter med Google Mobile Services og bør være blokkert.'
    Add-Line
    $restrictionRows = Get-RestrictionRows -Platforms @{ androidForWorkRestriction = 'Android Enterprise work profile'; androidRestriction = 'Android device administrator' }
    Add-Table -Headers @('Konfigurasjon', 'Prioritet', 'Plattform', 'Plattform blokkert', 'Personlige blokkert', 'Min OS', 'Maks OS') -Rows $restrictionRows
    foreach ($r in @($restrictionRows)) {
        if ($r[2] -eq 'Android device administrator' -and $r[3] -ne $true) { Add-Finding "Registreringsbegrensningen «$($r[0])» tillater Android device administrator. Blokker den (utgått på GMS-enheter)." }
    }
}

$script:AppGroupLabel = @{ selectedPublicApps = 'Valgte apper'; allCoreMicrosoftApps = 'Kjerne-Microsoft-apper'; allMicrosoftApps = 'Alle Microsoft-apper'; allApps = 'Alle apper' }

function Write-AppProtectionSection {
    param([Parameter(Mandatory = $true)][string]$Collection, [Parameter(Mandatory = $true)][string]$PlatformLabel)
    $rows = @()
    $policies = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/$Collection")
    foreach ($p in ($policies | Sort-Object { [string](Get-Prop $_ 'displayName') })) {
        $id = [string](Get-Prop $p 'id')
        $levels = [string](Get-Prop $p 'targetedAppManagementLevels')
        $assignments = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/$Collection/$id/assignments")
        $labels = @()
        $scopes = @()
        foreach ($a in $assignments) {
            $t = Get-TargetInfo -Target (Get-Prop $a 'target')
            $labels += $t.Label
            if ($t.Excluded) { continue }
            # Tolkning ut fra filteret, slik Microsoft anbefaler å målrette med/uten enrollment.
            if ($t.Filter -and $t.Filter.Rule -match 'deviceManagementType\s+-eq\s+"Unmanaged"') {
                $scopes += $(if ($t.FilterType -eq 'include') { 'Uten enrollment (MAM-WE)' } else { 'Bare registrerte enheter' })
            }
            elseif ($t.Filter -and $t.Filter.Rule -match 'deviceManagementType') {
                $scopes += "Filterregel: $($t.Filter.Rule) ($($t.FilterType))"
            }
            else {
                $scopes += 'Alle enhetstyper (uten filter)'
            }
        }
        if ($levels -and $levels -ne 'unspecified') { $scopes += "targetedAppManagementLevels: $levels" }
        $groupType = [string](Get-Prop $p 'appGroupType')
        if ($assignments.Count -eq 0) { Add-Finding "$PlatformLabel-app-beskyttelsespolicyen «$(Get-Prop $p 'displayName')» er ikke tildelt." }
        $rows += , @(
            (Get-Prop $p 'displayName'),
            $(if ($script:AppGroupLabel.ContainsKey($groupType)) { $script:AppGroupLabel[$groupType] } else { $groupType }),
            (Get-Prop $p 'deployedAppCount'),
            $(if ($labels.Count) { $labels -join '; ' } else { 'Ikke tildelt' }),
            $(if ($scopes.Count) { (@($scopes | Select-Object -Unique)) -join '; ' } else { '–' }),
            (Format-OsloTime (Get-Prop $p 'lastModifiedDateTime'))
        )
    }
    Add-Table -Headers @('Policy', 'Målapper', 'Apper i bruk (deployedAppCount)', 'Tildelt til', 'Med/uten enrollment', 'Sist endret (Oslo)') -Rows $rows
}

function Write-ManagedDeviceSection {
    $devices = @(Get-GraphCollection -Uri "$script:GraphV1/deviceManagement/managedDevices?`$select=operatingSystem,complianceState")
    $groups = $devices | Group-Object { "{0}|{1}" -f (Get-Prop $_ 'operatingSystem'), (Get-Prop $_ 'complianceState') }
    $rows = @($groups | Sort-Object Name | ForEach-Object { $parts = $_.Name -split '\|', 2; , @($parts[0], $parts[1], $_.Count) })
    Add-Line "Totalt $($devices.Count) administrerte enheter."
    Add-Line
    Add-Table -Headers @('Operativsystem', 'Samsvarsstatus', 'Antall') -Rows $rows
}

# -----------------------------------------------------------------------------
# Hovedflyt
# -----------------------------------------------------------------------------
Assert-AppOnlyParameterSet

$generatedUtc = [DateTimeOffset]::UtcNow
if (-not $OutputPath) {
    $stamp = [TimeZoneInfo]::ConvertTime($generatedUtc, $script:OsloZone).ToString('yyyyMMdd-HHmm', [Globalization.CultureInfo]::InvariantCulture)
    $OutputPath = ".\Intune-forutsetningsrapport-$stamp.md"
}
$fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

$scopes = @(
    'DeviceManagementApps.Read.All',
    'DeviceManagementConfiguration.Read.All',
    'DeviceManagementServiceConfig.Read.All',
    'Group.Read.All'
)
if ($IncludeManagedDeviceSummary) { $scopes += 'DeviceManagementManagedDevices.Read.All' }

Import-GraphAuthenticationModule
Connect-IntuneGraph -Scopes $scopes
$context = Get-MgContext

Invoke-ReportSection -Title '1. Publiserte apper og tildelinger' -Script { Write-AppsSection }
Invoke-ReportSection -Title '2. Grupper og tildelte apper' -Script { Write-GroupIndexSection }
Invoke-ReportSection -Title '3. Samsvarspolicyer og berørte enheter' -Script { Write-ComplianceSection }
Add-Line '## 4. Registrering (enrollment)'
Add-Line
Invoke-ReportSection -Level 3 -Title '4a. iOS/iPadOS' -Script { Write-IosEnrollmentSection }
Invoke-ReportSection -Level 3 -Title '4b. Android' -Script { Write-AndroidEnrollmentSection }
Add-Line '## 5. App-beskyttelsespolicyer (APP/MAM)'
Add-Line
Invoke-ReportSection -Level 3 -Title '5a. iOS/iPadOS' -Script { Write-AppProtectionSection -Collection 'iosManagedAppProtections' -PlatformLabel 'iOS' }
Invoke-ReportSection -Level 3 -Title '5b. Android' -Script { Write-AppProtectionSection -Collection 'androidManagedAppProtections' -PlatformLabel 'Android' }
if ($IncludeManagedDeviceSummary) {
    Invoke-ReportSection -Title '6. Administrerte enheter' -Script { Write-ManagedDeviceSection }
}

# Topptekst og funn settes først i rapporten.
$header = New-Object System.Collections.Generic.List[string]
$header.Add('# Intune-forutsetningsrapport')
$header.Add('')
$header.Add("- **Generert:** $(Format-OsloTime $generatedUtc -WithZone)")
$header.Add("- **Tenant:** $(if ($context) { $context.TenantId } else { '–' })")
$header.Add("- **Kjørt av:** $(if ($context -and $context.Account) { $context.Account } elseif ($context) { "App $($context.ClientId) (app-only)" } else { '–' })")
$header.Add("- **Graph-rettigheter:** $($scopes -join ', ')")
$header.Add('- **Script:** Get-IntunePreDeploymentReport.ps1 (bare lesing)')
$header.Add('')
$header.Add('## 0. Funn før utrulling')
$header.Add('')
if ($script:Findings.Count -eq 0) { $header.Add('_Ingen automatiske funn. Gå likevel gjennom avsnittene under._') }
else { foreach ($f in $script:Findings) { $header.Add("- $f") } }
$header.Add('')

$all = New-Object System.Collections.Generic.List[string]
$all.AddRange($header)
$all.AddRange($script:Body)

if ($PSCmdlet.ShouldProcess($fullPath, 'Skriv rapportfil')) {
    $dir = Split-Path -Parent $fullPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # UTF-8 uten BOM passer best for Markdown, Git og innliming i Confluence.
    [IO.File]::WriteAllLines($fullPath, $all.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Rapport lagret: $fullPath"
}

if (-not $NoConsoleOutput) {
    Write-Host ''
    foreach ($line in $all) { Write-Host $line }
}
Write-Host "Funn: $($script:Findings.Count). Generert $(Format-OsloTime $generatedUtc -WithZone)."
