#Requires -Version 5.1
# UTF-8 med BOM, slik at æ/ø/å vises riktig også i Windows PowerShell 5.1.
<#
.SYNOPSIS
    Publiserer og tildeler en iPhone/iPad-app i Intune: App Store, VPP (Apple Business),
    webklipp, eller en eksisterende app som for eksempel en LOB-app (.ipa).

.DESCRIPTION
    Scriptet dekker de fire vanlige måtene å distribuere iOS/iPadOS-apper på, og er laget
    for å være trygt å kjøre flere ganger (ingen duplikater):

      -AppStoreId  App Store-app. Scriptet slår opp appen i Apples offentlige oppslags-API
                   (samme data som admin-senteret viser), og oppretter en iosStoreApp
                   hvis den ikke finnes fra før (samme bundle-ID).
                   Uten VPP må brukeren selv ha Apple-konto for å installere.

      -VppBundleId VPP-app kjøpt i Apple Business (Apps and Books). Slike apper kan IKKE
                   opprettes med Graph. De synkroniseres inn fra VPP-/plasseringstokenet.
                   Scriptet finner appen, og kan be om ny synk (-SyncVppToken).
                   Enhetslisensiering (standard) krever ingen Apple-konto på enheten.
                   Dette er anbefalt for firmaeide enheter og for Company Portal på ADE.

      -WebClipUrl  iOS/iPadOS-webklipp (snarvei på hjemskjermen), kan tvinges til Edge.

      -AppId       En app som allerede finnes i Intune, typisk en LOB-app (.ipa) lastet opp
                   i admin-senteret. Scriptet kontrollerer at det er en iOS-apptype og tildeler.

    Hvorfor LOB (.ipa) ikke lastes opp her:
      Opplasting av .ipa krever lesing av Info.plist og provisjoneringsprofil (bundle-ID,
      versjon, build, utløpsdato), kryptering av pakken og opplasting av innhold i flere
      steg. Microsoft dokumenterer flyten i admin-senteret (Apps > All Apps > Create >
      iOS/iPadOS > Line-of-business app). For å unngå et halvferdig script uten offisiell
      oppskrift: last opp .ipa i admin-senteret, og bruk deretter -AppId her for tildeling
      på samme måte som de andre appene. Provisjoneringsprofilen må fornyes før den utløper
      (Intune varsler 30 dager før).

    Forutsetninger som IKKE kan scriptes (scriptet sjekker det som kan sjekkes):
      - Apple MDM Push-sertifikat (APNs) må være lastet opp i Intune. Uten det kan ingen
        iPhone registreres eller få apper fra Intune. Sertifikatet gjelder i 365 dager.
        Scriptet stopper hvis det mangler eller er utløpt, og advarer ved under 30 dager.
      - For VPP: et gyldig VPP-/plasseringstoken fra Apple Business, lastet opp under
        Tenant administration > Connectors and tokens > Apple VPP tokens, og appen kjøpt
        (lisenser) i Apple Business. Scriptet sjekker tokenstatus.
      - Required-tildeling krever at enheten er registrert i Intune. På overvåkede
        (supervised) ADE-enheter installeres appen stille. På andre får brukeren spørsmål.

    Plattformforskjell mot Android: på iOS er det App Store/VPP og .ipa. På Android er det
    Managed Google Play, se ..\mobile-android\New-IntuneAndroidManagedPlayOrLobApp.ps1.

.PARAMETER AppStoreId
    Numerisk App Store-ID (tallet etter "id" i App Store-lenken), for eksempel 618783545.

.PARAMETER CountryCode
    Landkode for App Store-oppslaget. Standard: no.

.PARAMETER VppBundleId
    Bundle-ID for en VPP-app som er synkronisert fra Apple Business, for eksempel com.tinyspeck.chatlyio.

.PARAMETER SyncVppToken
    Be Intune synkronisere VPP-lisenser hvis VPP-appen ikke finnes ennå. Synk går i bakgrunnen.

.PARAMETER WebClipUrl
    HTTPS-adresse for webklipp. Brukes sammen med -DisplayName.

.PARAMETER UseManagedBrowser
    Webklipp åpnes i Microsoft Edge. På som standard.

.PARAMETER AppId
    Intune-ID for en eksisterende iOS-app (LOB, Store, VPP eller webklipp).

.PARAMETER DisplayName
    Visningsnavn. Påkrevd for webklipp, valgfritt ellers (App Store-navnet brukes).

.PARAMETER Publisher
    Utgiver som vises i Company Portal for webklipp. Standard: IT.

.PARAMETER GroupId
    Objekt-ID for Entra-gruppen som skal få appen.

.PARAMETER GroupName
    Visningsnavn for gruppen hvis du ikke har ID. Krever Group.Read.All.

.PARAMETER Intent
    Required, Available eller Uninstall. Available (i Company Portal) må tildeles brukergrupper på iOS.

.PARAMETER UseDeviceLicensing
    VPP: bruk enhetslisens (ingen Apple-konto). På som standard.

.PARAMETER IsRemovable
    App Store/LOB: om brukeren kan avinstallere appen. Standard: $true.

.PARAMETER UninstallOnDeviceRemoval
    App Store/LOB: avinstaller appen når enheten fjernes fra Intune. Standard: $true.

.PARAMETER SkipAssignment
    Bare publiser, ikke tildel.

.PARAMETER TenantId
    Tenant-ID. Valgfri ved interaktiv pålogging, påkrevd sammen med sertifikat.

.PARAMETER ClientId
    App-registreringens program-ID ved app-only-pålogging med sertifikat.

.PARAMETER CertificateThumbprint
    Tommelavtrykk for sertifikatet i lokalt sertifikatlager. App-only, uten hemmelighet.

.EXAMPLE
    # Slack fra App Store, tilgjengelig i Company Portal for pilotbrukere
    .\New-IntuneIosStoreOrLobApp.ps1 -AppStoreId 618783545 -GroupName 'Pilot - Slack iOS - Brukere' -Intent Available -WhatIf

.EXAMPLE
    # VPP-app med enhetslisens, påkrevd på firmaeide iPhoner
    .\New-IntuneIosStoreOrLobApp.ps1 -VppBundleId 'com.tinyspeck.chatlyio' -GroupId '<enhetsgruppe-id>' -Intent Required

.EXAMPLE
    # LOB-app (.ipa) lastet opp i admin-senteret, tildeles her
    .\New-IntuneIosStoreOrLobApp.ps1 -AppId '<intune-app-id>' -GroupId '<gruppe-id>' -Intent Required

.EXAMPLE
    .\New-IntuneIosStoreOrLobApp.ps1 -WebClipUrl 'https://intranett.example.no' -DisplayName 'Intranett' -GroupId '<gruppe-id>' -Intent Available

.NOTES
    Minste Graph-rettigheter:
      - DeviceManagementApps.ReadWrite.All       (opprette app, tildele, VPP-synk)
      - DeviceManagementServiceConfig.Read.All   (lese APNs-sertifikat og VPP-token)
      - Group.Read.All                           (bare ved -GroupName)

    Graph-versjoner: App Store-appen opprettes på beta fordi v1.0 bare har minimum
    iOS-versjon til og med 15.0 (beta har 16, 17, 18 og 26). Alt annet bruker v1.0.
    Tildeling legges til med POST /mobileApps/{id}/assignments, slik at eksisterende
    tildelinger på appen beholdes.

    Apples oppslags-API (itunes.apple.com/lookup) er offentlig og krever ingen pålogging.

    Kilder (sjekket 10. november 2026):
      https://learn.microsoft.com/en-us/intune/app-management/deployment/add-lob-ios
      https://learn.microsoft.com/en-us/intune/app-management/deployment/manage-vpp-apple
      https://learn.microsoft.com/en-us/intune/device-enrollment/apple/create-mdm-push-certificate
      https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-iosstoreapp?view=graph-rest-1.0
      https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-iosvppapp?view=graph-rest-1.0
      https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-iosipadoswebclip?view=graph-rest-1.0
      https://learn.microsoft.com/en-us/graph/api/intune-apps-mobileappassignment-create?view=graph-rest-1.0
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Store')]
param(
    [Parameter(ParameterSetName = 'Store', Mandatory = $true)]
    [ValidatePattern('^\d+$')]
    [string]$AppStoreId,

    [Parameter(ParameterSetName = 'Store')]
    [ValidatePattern('^[a-zA-Z]{2}$')]
    [string]$CountryCode = 'no',

    [Parameter(ParameterSetName = 'Vpp', Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9\.\-]+$')]
    [string]$VppBundleId,

    [Parameter(ParameterSetName = 'Vpp')]
    [switch]$SyncVppToken,

    [Parameter(ParameterSetName = 'Vpp')]
    [bool]$UseDeviceLicensing = $true,

    [Parameter(ParameterSetName = 'WebClip', Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$WebClipUrl,

    [Parameter(ParameterSetName = 'WebClip')]
    [bool]$UseManagedBrowser = $true,

    [Parameter(ParameterSetName = 'WebClip')]
    [string]$Publisher = 'IT',

    [Parameter(ParameterSetName = 'Existing', Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$AppId,

    [string]$DisplayName,

    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$GroupId,

    [string]$GroupName,

    [ValidateSet('Required', 'Available', 'Uninstall')]
    [string]$Intent = 'Available',

    [bool]$IsRemovable = $true,

    [bool]$UninstallOnDeviceRemoval = $true,

    [switch]$SkipAssignment,

    [string]$TenantId,

    [string]$ClientId,

    [string]$CertificateThumbprint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'

# iOS-apptyper som kan tildeles med dette scriptet.
$script:IosAppTypes = @(
    '#microsoft.graph.iosStoreApp',
    '#microsoft.graph.iosVppApp',
    '#microsoft.graph.iosLobApp',
    '#microsoft.graph.iosiPadOSWebClip',
    '#microsoft.graph.managedIOSStoreApp',
    '#microsoft.graph.managedIOSLobApp'
)

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
# iOS-forutsetninger
# -----------------------------------------------------------------------------
function Assert-ApplePushCertificate {
    <#
    .SYNOPSIS
        Stopper hvis APNs-sertifikatet mangler eller er utløpt. Advarer ved under 30 dager igjen.
    #>
    $cert = $null
    try {
        $cert = Invoke-Graph -Uri "$script:GraphV1/deviceManagement/applePushNotificationCertificate?`$select=appleIdentifier,expirationDateTime,topicIdentifier"
    }
    catch {
        throw "Fant ikke Apple MDM Push-sertifikat (APNs) i Intune. Last det opp under Devices > Enrollment > Apple > Apple MDM Push certificate før iOS-apper kan distribueres. Detaljer: $($_.Exception.Message)"
    }
    $expires = Get-Prop $cert 'expirationDateTime'
    if (-not $expires) {
        throw "APNs-sertifikatet er ikke konfigurert (ingen utløpsdato). Last det opp i Intune før du fortsetter."
    }
    $expiresAt = ConvertTo-DateTimeOffsetValue $expires
    $daysLeft = [math]::Floor(($expiresAt - [DateTimeOffset]::UtcNow).TotalDays)
    if ($daysLeft -lt 0) {
        throw "APNs-sertifikatet utløp $($expiresAt.ToLocalTime().ToString('yyyy-MM-dd')). Forny det med SAMME Apple-konto ($(Get-Prop $cert 'appleIdentifier')), ellers må alle iPhoner registreres på nytt."
    }
    if ($daysLeft -lt 30) {
        Write-Warning "APNs-sertifikatet utløper om $daysLeft dager. Forny det snart med samme Apple-konto."
    }
    Write-Host "APNs-sertifikat OK (utløper $($expiresAt.ToLocalTime().ToString('yyyy-MM-dd')), $daysLeft dager igjen)."
}

function Get-ValidVppTokens {
    <#
    .SYNOPSIS
        Henter VPP-token uten selve tokenverdien, og stopper hvis ingen er gyldige.
    #>
    $tokens = @(Get-GraphCollection -Uri "$script:GraphV1/deviceAppManagement/vppTokens?`$select=id,organizationName,state,expirationDateTime,lastSyncDateTime,lastSyncStatus,countryOrRegion")
    if ($tokens.Count -eq 0) {
        throw "Ingen VPP-/plasseringstoken i Intune. Last ned token fra Apple Business og last det opp under Tenant administration > Connectors and tokens > Apple VPP tokens."
    }
    $valid = @($tokens | Where-Object { (Get-Prop $_ 'state') -eq 'valid' })
    foreach ($t in $tokens) {
        Write-Host ("VPP-token: {0} | status {1} | utløper {2} | siste synk {3}" -f (Get-Prop $t 'organizationName'), (Get-Prop $t 'state'), (Get-Prop $t 'expirationDateTime'), (Get-Prop $t 'lastSyncDateTime'))
    }
    if ($valid.Count -eq 0) {
        throw "Ingen gyldige VPP-token. Forny tokenet i Apple Business og last det opp på nytt i det EKSISTERENDE tokenet i Intune (ikke opprett et nytt)."
    }
    return $valid
}

function Get-IosMinimumOsObject {
    <#
    .SYNOPSIS
        Gjør Apples minimumOsVersion om til Intunes iosMinimumOperatingSystem (nøyaktig ett felt er sant).
    #>
    param([string]$MinimumOsVersion)
    # Verdiene som finnes i Graph beta per november 2026. Apple hoppet fra 18 til 26.
    $supported = @(8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 26)
    $major = 15
    if ($MinimumOsVersion -match '^(\d+)') { $major = [int]$Matches[1] }
    $chosen = ($supported | Where-Object { $_ -le $major } | Measure-Object -Maximum).Maximum
    if (-not $chosen) { $chosen = 8 }
    $result = [ordered]@{ '@odata.type' = '#microsoft.graph.iosMinimumOperatingSystem' }
    foreach ($v in $supported) { $result["v$($v)_0"] = ($v -eq $chosen) }
    return $result
}

function Find-MobileApp {
    <#
    .SYNOPSIS
        Finner apper av en gitt type som matcher et filter, i hele app-listen (med paginering).
    #>
    param([Parameter(Mandatory = $true)][string]$ODataType, [Parameter(Mandatory = $true)][scriptblock]$Match)
    return @(Get-GraphCollection -Uri "$script:GraphV1/deviceAppManagement/mobileApps" |
            Where-Object { (Get-Prop $_ '@odata.type') -eq $ODataType } |
            Where-Object $Match)
}

function Get-OrNewIosStoreApp {
    Write-Host "Slår opp App Store-ID $AppStoreId ($CountryCode) hos Apple..."
    # Windows PowerShell 5.1 kan mangle TLS 1.2 som standard. Legg det til uten å fjerne annet.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $lookup = Invoke-RestMethod -Uri "https://itunes.apple.com/lookup?id=$AppStoreId&country=$CountryCode" -Method Get
    if (-not $lookup -or $lookup.resultCount -lt 1) {
        throw "Fant ingen app med App Store-ID $AppStoreId i landet '$CountryCode'."
    }
    $info = $lookup.results[0]
    $bundleId = [string]$info.bundleId
    Write-Host "Fant '$($info.trackName)' fra $($info.sellerName) (bundle-ID $bundleId, krever iOS $($info.minimumOsVersion))."

    $existing = @(Find-MobileApp -ODataType '#microsoft.graph.iosStoreApp' -Match { (Get-Prop $_ 'bundleId') -eq $bundleId })
    if ($existing.Count -ge 1) {
        if ($existing.Count -gt 1) { Write-Warning "Fant $($existing.Count) App Store-apper med bundle-ID $bundleId. Bruker den første. Vurder å rydde opp." }
        Write-Host "App Store-appen finnes allerede i Intune ($(Get-Prop $existing[0] 'id')). Ingen ny app opprettes."
        return $existing[0]
    }

    $devices = @($info.supportedDevices)
    $iPhone = @($devices | Where-Object { $_ -like 'iPhone*' }).Count -gt 0
    $iPad = @($devices | Where-Object { $_ -like 'iPad*' }).Count -gt 0
    if (-not $iPhone -and -not $iPad) { $iPhone = $true; $iPad = $true }

    $name = if ($DisplayName) { $DisplayName } else { [string]$info.trackName }
    $body = [ordered]@{
        '@odata.type'                   = '#microsoft.graph.iosStoreApp'
        displayName                     = $name
        description                     = "App Store-app lagt til med New-IntuneIosStoreOrLobApp.ps1. $([string]$info.trackViewUrl)"
        publisher                       = [string]$info.sellerName
        bundleId                        = $bundleId
        appStoreUrl                     = [string]$info.trackViewUrl
        informationUrl                  = [string]$info.trackViewUrl
        applicableDeviceType            = @{ '@odata.type' = '#microsoft.graph.iosDeviceType'; iPad = $iPad; iPhoneAndIPod = $iPhone }
        minimumSupportedOperatingSystem = (Get-IosMinimumOsObject -MinimumOsVersion ([string]$info.minimumOsVersion))
    }
    if (-not $PSCmdlet.ShouldProcess($name, 'Opprett iOS App Store-app i Intune')) {
        Write-Host "WhatIf: ville opprettet iosStoreApp '$name' ($bundleId)."
        return $null
    }
    $app = Invoke-Graph -Method POST -Uri "$script:GraphBeta/deviceAppManagement/mobileApps" -Body $body
    Write-Host "Opprettet App Store-appen '$name' ($(Get-Prop $app 'id'))."
    return $app
}

function Get-IosVppApp {
    $tokens = Get-ValidVppTokens
    $apps = @(Find-MobileApp -ODataType '#microsoft.graph.iosVppApp' -Match { (Get-Prop $_ 'bundleId') -eq $VppBundleId })
    if ($apps.Count -eq 0) {
        $message = "Fant ingen VPP-app med bundle-ID $VppBundleId. Kjøp (lisenser) appen i Apple Business under Apps and Books, med samme plassering som tokenet."
        if ($SyncVppToken) {
            foreach ($t in @($tokens)) {
                if ($PSCmdlet.ShouldProcess((Get-Prop $t 'organizationName'), 'Synkroniser VPP-lisenser')) {
                    Invoke-Graph -Method POST -Uri "$script:GraphV1/deviceAppManagement/vppTokens/$(Get-Prop $t 'id')/syncLicenses" | Out-Null
                    Write-Host "Ba om VPP-synk for $(Get-Prop $t 'organizationName')."
                }
            }
            $message += " VPP-synk er startet. Kjør scriptet på nytt om noen minutter."
        }
        else {
            $message += " Kjør på nytt med -SyncVppToken hvis appen nettopp er kjøpt."
        }
        throw $message
    }
    if ($apps.Count -gt 1) {
        $list = ($apps | ForEach-Object { "$(Get-Prop $_ 'displayName') / $(Get-Prop $_ 'vppTokenOrganizationName') ($(Get-Prop $_ 'id'))" }) -join '; '
        throw "Fant flere VPP-apper med bundle-ID $VppBundleId (flere token?): $list. Bruk -AppId for å velge riktig."
    }
    $app = $apps[0]
    Write-Host ("Fant VPP-appen '{0}' ({1}). Lisenser: {2} brukt av {3}." -f (Get-Prop $app 'displayName'), (Get-Prop $app 'id'), (Get-Prop $app 'usedLicenseCount'), (Get-Prop $app 'totalLicenseCount'))
    return $app
}

function Get-OrNewIosWebClip {
    if (-not $DisplayName) { throw "-DisplayName er påkrevd for webklipp." }
    $existing = @(Find-MobileApp -ODataType '#microsoft.graph.iosiPadOSWebClip' -Match { (Get-Prop $_ 'appUrl') -eq $WebClipUrl })
    if ($existing.Count -ge 1) {
        Write-Host "Webklippet for $WebClipUrl finnes allerede ($(Get-Prop $existing[0] 'id'))."
        return $existing[0]
    }
    $body = [ordered]@{
        '@odata.type'     = '#microsoft.graph.iosiPadOSWebClip'
        displayName       = $DisplayName
        description       = "Webklipp til $WebClipUrl, lagt til med New-IntuneIosStoreOrLobApp.ps1."
        publisher         = $Publisher
        appUrl            = $WebClipUrl
        useManagedBrowser = $UseManagedBrowser
    }
    if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Opprett iOS/iPadOS-webklipp')) {
        Write-Host "WhatIf: ville opprettet webklipp '$DisplayName' til $WebClipUrl."
        return $null
    }
    $app = Invoke-Graph -Method POST -Uri "$script:GraphV1/deviceAppManagement/mobileApps" -Body $body
    Write-Host "Opprettet webklippet '$DisplayName' ($(Get-Prop $app 'id'))."
    return $app
}

function Get-ExistingIosApp {
    $app = Invoke-Graph -Uri "$script:GraphV1/deviceAppManagement/mobileApps/$AppId"
    $type = [string](Get-Prop $app '@odata.type')
    if ($script:IosAppTypes -notcontains $type) {
        throw "App $AppId er av typen $(if ($type) { $type } else { "ukjent" }), ikke en iOS-app. Bruk riktig script for plattformen."
    }
    Write-Host "Fant '$(Get-Prop $app 'displayName')' ($type)."
    if ($type -eq '#microsoft.graph.iosLobApp') {
        $exp = Get-Prop $app 'expirationDateTime'
        if ($exp) {
            $days = [math]::Floor(((ConvertTo-DateTimeOffsetValue $exp) - [DateTimeOffset]::UtcNow).TotalDays)
            if ($days -lt 0) { throw "Provisjoneringsprofilen til LOB-appen er utløpt. Last opp en ny .ipa i admin-senteret." }
            if ($days -lt 30) { Write-Warning "Provisjoneringsprofilen til LOB-appen utløper om $days dager." }
        }
    }
    return $app
}

function Get-IosAssignmentSettings {
    <#
    .SYNOPSIS
        Velger riktige tildelingsinnstillinger per iOS-apptype. Uninstall har ingen innstillinger.
    #>
    param([string]$ODataType)
    if ($Intent -eq 'Uninstall') { return $null }
    switch ($ODataType) {
        '#microsoft.graph.iosVppApp' {
            # Enhetslisens: appen knyttes til enheten, ingen Apple-konto kreves.
            return @{ '@odata.type' = '#microsoft.graph.iosVppAppAssignmentSettings'; useDeviceLicensing = $UseDeviceLicensing }
        }
        '#microsoft.graph.iosStoreApp' {
            return @{ '@odata.type' = '#microsoft.graph.iosStoreAppAssignmentSettings'; isRemovable = $IsRemovable; uninstallOnDeviceRemoval = $UninstallOnDeviceRemoval }
        }
        '#microsoft.graph.iosLobApp' {
            return @{ '@odata.type' = '#microsoft.graph.iosLobAppAssignmentSettings'; isRemovable = $IsRemovable; uninstallOnDeviceRemoval = $UninstallOnDeviceRemoval }
        }
        default { return $null }
    }
}

function Add-MobileAppAssignment {
    <#
    .SYNOPSIS
        Legger til én gruppetildeling på appen uten å røre eksisterende tildelinger.
    #>
    param([Parameter(Mandatory = $true)]$App, [Parameter(Mandatory = $true)][string]$TargetGroupId, $Settings)

    $id = [string](Get-Prop $App 'id')
    $intentValue = $Intent.ToLowerInvariant()
    $current = @(Get-GraphCollection -Uri "$script:GraphV1/deviceAppManagement/mobileApps/$id/assignments")
    foreach ($a in $current) {
        if ((Get-Prop (Get-Prop $a 'target') 'groupId') -eq $TargetGroupId) {
            if ((Get-Prop $a 'intent') -eq $intentValue) {
                Write-Host "Gruppen har allerede tildelingen $Intent. Ingen endring."
                return
            }
            throw "Gruppen er allerede tildelt appen med intent '$(Get-Prop $a 'intent')'. Endre tildelingen i Intune manuelt hvis det er meningen."
        }
    }

    $body = [ordered]@{
        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
        intent        = $intentValue
        target        = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $TargetGroupId }
    }
    if ($null -ne $Settings) { $body.settings = $Settings }

    if (-not $PSCmdlet.ShouldProcess("$(Get-Prop $App 'displayName') ($id)", "Tildel $Intent til gruppe $TargetGroupId")) {
        Write-Host "WhatIf: ville tildelt $Intent til gruppe $TargetGroupId."
        return
    }
    Invoke-Graph -Method POST -Uri "$script:GraphV1/deviceAppManagement/mobileApps/$id/assignments" -Body $body | Out-Null
    Write-Host "Tildelt $Intent til gruppe $TargetGroupId."
}

# -----------------------------------------------------------------------------
# Hovedflyt
# -----------------------------------------------------------------------------
Assert-AppOnlyParameterSet
if (-not $SkipAssignment -and -not $GroupId -and -not $GroupName) {
    throw "Oppgi -GroupId eller -GroupName, eller bruk -SkipAssignment."
}
if ($GroupId -and $GroupName) { throw "Bruk enten -GroupId eller -GroupName, ikke begge." }

$scopes = @('DeviceManagementApps.ReadWrite.All', 'DeviceManagementServiceConfig.Read.All')
if ($GroupName) { $scopes += 'Group.Read.All' }

Write-Host "Plattform: iOS/iPadOS | metode: $($PSCmdlet.ParameterSetName) | intent: $Intent"
Import-GraphAuthenticationModule
Connect-IntuneGraph -Scopes $scopes

# APNs er grunnmuren for all iOS-administrasjon i Intune.
Assert-ApplePushCertificate

$app = switch ($PSCmdlet.ParameterSetName) {
    'Store' { Get-OrNewIosStoreApp }
    'Vpp' { Get-IosVppApp }
    'WebClip' { Get-OrNewIosWebClip }
    'Existing' { Get-ExistingIosApp }
}

if ($SkipAssignment) {
    Write-Host "Tildeling hoppet over (-SkipAssignment)."
    return $app
}

$targetGroupId = Resolve-EntraGroupId -Id $GroupId -Name $GroupName
if ($Intent -eq 'Available') {
    Write-Host "Merk: Available på iOS vises i Company Portal og må tildeles en brukergruppe, ikke en enhetsgruppe."
}

if (-not $app) {
    Write-Host "WhatIf: appen finnes ikke ennå, så tildeling til $targetGroupId ($Intent) vises bare som plan."
    return
}

$settings = Get-IosAssignmentSettings -ODataType ([string](Get-Prop $app '@odata.type'))
Add-MobileAppAssignment -App $app -TargetGroupId $targetGroupId -Settings $settings
Write-Host "Ferdig. Følg installasjonsstatus i Intune under Apps > All Apps > $(Get-Prop $app 'displayName') > Device install status."
return $app
