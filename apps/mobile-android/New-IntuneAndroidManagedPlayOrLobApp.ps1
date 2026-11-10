#Requires -Version 5.1
# UTF-8 med BOM, slik at æ/ø/å vises riktig også i Windows PowerShell 5.1.
<#
.SYNOPSIS
    Tildeler en Android-app i Intune via Managed Google Play (foretrukket), eller tildeler
    en eksisterende Android-app som en LOB-app (.apk).

.DESCRIPTION
    Android Enterprise i Intune bruker Managed Google Play som appkilde. Apper må være
    godkjent i Managed Google Play og synkronisert inn i Intune før de kan tildeles.
    Det gjelder offentlige Play-apper, private apper (egne .apk/.aab publisert privat)
    og Managed Google Play-nettapper (web-lenker).

    Scriptet kan:

      -PackageId   Finne Managed Google Play-appen (androidManagedStoreApp) med dette
                   pakkenavnet og tildele den. Finnes den ikke, stopper scriptet med
                   instruks, ELLER (med -ApproveAndSync -ApproveAllPermissions) godkjenner
                   appen og synkroniserer via Graph beta, og venter til den dukker opp.

      -AppId       Tildele en app som allerede finnes i Intune, for eksempel en
                   Managed Google Play-nettapp eller en LOB-app (.apk) lastet opp i
                   admin-senteret.

    Forutsetninger som IKKE kan scriptes (scriptet sjekker det som kan sjekkes):
      - Intune-tenanten må være koblet til Managed Google Play (Devices > Enrollment >
        Android > Prerequisites > Managed Google Play). Koblingen krever pålogging hos
        Google i nettleseren med en Entra-konto med postkasse. Scriptet leser bindStatus
        og stopper hvis tenanten ikke er koblet. Det går ikke an å godkjenne eller laste
        opp Play-apper uten denne koblingen.
      - Private apper (.apk/.aab) lastes opp i Managed Google Play-vinduet i admin-senteret
        (Private apps) eller i Google Play Console, ikke via Graph.
      - Direkte LOB (.apk uten Managed Google Play) støttes bare på Android Enterprise
        fully managed og dedikerte enheter. Til work profile (BYOD og COPE) skal appen
        publiseres som privat app i Managed Google Play.

    Plattformforskjell mot iOS: ingen Apple-token, APNs eller VPP. Til gjengjeld må
    Managed Google Play være koblet, og godkjenning av apptillatelser skjer hos Google.

.PARAMETER PackageId
    Android-pakkenavn, for eksempel com.Slack.

.PARAMETER ApproveAndSync
    Hvis appen ikke finnes i Intune: godkjenn den i Managed Google Play og synkroniser.
    Bruker beta-handlingene approveApps og syncApps. Krever -ApproveAllPermissions.

.PARAMETER ApproveAllPermissions
    Bekrefter at du godkjenner alle tillatelsene appen ber om, på vegne av organisasjonen.
    Kontroller tillatelsene i Google Play først. Kreves sammen med -ApproveAndSync.

.PARAMETER SyncTimeoutMinutes
    Hvor lenge scriptet venter på at appen dukker opp etter synk. Standard 10.

.PARAMETER AppId
    Intune-ID for en eksisterende Android-app.

.PARAMETER GroupId
    Objekt-ID for Entra-gruppen som skal få appen.

.PARAMETER GroupName
    Visningsnavn for gruppen hvis du ikke har ID. Krever Group.Read.All.

.PARAMETER Intent
    Required, Available eller Uninstall.

.PARAMETER SkipAssignment
    Bare finn eller godkjenn appen, ikke tildel.

.PARAMETER TenantId
    Tenant-ID. Valgfri ved interaktiv pålogging, påkrevd sammen med sertifikat.

.PARAMETER ClientId
    App-registreringens program-ID ved app-only-pålogging med sertifikat.

.PARAMETER CertificateThumbprint
    Tommelavtrykk for sertifikatet i lokalt sertifikatlager. App-only, uten hemmelighet.

.EXAMPLE
    # Slack fra Managed Google Play, tilgjengelig for pilotbrukere
    .\New-IntuneAndroidManagedPlayOrLobApp.ps1 -PackageId 'com.Slack' -GroupName 'Pilot - Slack Android - Brukere' -Intent Available -WhatIf

.EXAMPLE
    # Godkjenn og synk hvis appen ikke er lagt til ennå
    .\New-IntuneAndroidManagedPlayOrLobApp.ps1 -PackageId 'com.Slack' -ApproveAndSync -ApproveAllPermissions -GroupId '<gruppe-id>' -Intent Required

.EXAMPLE
    # LOB-app (.apk) til fully managed-enheter
    .\New-IntuneAndroidManagedPlayOrLobApp.ps1 -AppId '<intune-app-id>' -GroupId '<enhetsgruppe-id>' -Intent Required

.NOTES
    Minste Graph-rettigheter:
      - DeviceManagementApps.ReadWrite.All           (finne og tildele app)
      - DeviceManagementConfiguration.Read.All       (lese Managed Google Play-kobling)
        DeviceManagementConfiguration.ReadWrite.All  (i stedet, bare med -ApproveAndSync)
      - Group.Read.All                               (bare ved -GroupName)

    Graph-versjoner: alt bruker beta. Ressurstypen androidManagedStoreApp er bare
    dokumentert i Graph beta (sjekket 10.11.2026), og det samme gjelder
    androidManagedStoreAccountEnterpriseSettings og handlingene approveApps/syncApps. Microsoft dokumenterer godkjenning i admin-senteret som hovedvei.
    approveApps er dokumentert i Graph-referansen, men har lite veiledning utover den.
    Bruk derfor -ApproveAndSync bevisst, og helst i pilot først.

    Kilder (sjekket 10. november 2026):
      https://learn.microsoft.com/en-us/intune/device-enrollment/android/connect-managed-google-play
      https://learn.microsoft.com/en-us/intune/app-management/deployment/add-managed-google-play
      https://learn.microsoft.com/en-us/intune/app-management/deployment/add-lob-android
      https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-androidmanagedstoreapp?view=graph-rest-1.0
      https://learn.microsoft.com/en-us/graph/api/resources/intune-androidforwork-androidmanagedstoreaccountenterprisesettings?view=graph-rest-beta
      https://learn.microsoft.com/en-us/graph/api/intune-androidforwork-androidmanagedstoreaccountenterprisesettings-approveapps?view=graph-rest-beta
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ManagedGooglePlay')]
param(
    [Parameter(ParameterSetName = 'ManagedGooglePlay', Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$')]
    [string]$PackageId,

    [Parameter(ParameterSetName = 'ManagedGooglePlay')]
    [switch]$ApproveAndSync,

    [Parameter(ParameterSetName = 'ManagedGooglePlay')]
    [switch]$ApproveAllPermissions,

    [Parameter(ParameterSetName = 'ManagedGooglePlay')]
    [ValidateRange(1, 60)]
    [int]$SyncTimeoutMinutes = 10,

    [Parameter(ParameterSetName = 'Existing', Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$AppId,

    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$GroupId,

    [string]$GroupName,

    [ValidateSet('Required', 'Available', 'Uninstall')]
    [string]$Intent = 'Available',

    [switch]$SkipAssignment,

    [string]$TenantId,

    [string]$ClientId,

    [string]$CertificateThumbprint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'

# Android-apptyper som kan tildeles med dette scriptet, og hva de betyr.
$script:AndroidAppTypes = @{
    '#microsoft.graph.androidManagedStoreApp'    = 'Managed Google Play-app (Android Enterprise)'
    '#microsoft.graph.androidManagedStoreWebApp' = 'Managed Google Play-nettapp (web-lenke)'
    '#microsoft.graph.androidLobApp'             = 'LOB-app (.apk), direkte'
    '#microsoft.graph.managedAndroidLobApp'      = 'LOB-app for app-beskyttelse (MAM)'
    '#microsoft.graph.managedAndroidStoreApp'    = 'Google Play-app for app-beskyttelse (MAM)'
    '#microsoft.graph.androidStoreApp'           = 'Google Play-lenke (ikke Android Enterprise)'
}

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
# Android-forutsetninger
# -----------------------------------------------------------------------------
function Assert-ManagedGooglePlayBinding {
    <#
    .SYNOPSIS
        Stopper hvis Intune ikke er koblet til Managed Google Play.
    #>
    $settings = $null
    try {
        $settings = Invoke-Graph -Uri "$script:GraphBeta/deviceManagement/androidManagedStoreAccountEnterpriseSettings?`$select=bindStatus,lastAppSyncDateTime,lastAppSyncStatus,ownerOrganizationName"
    }
    catch {
        throw "Kunne ikke lese Managed Google Play-koblingen. Kontroller rettigheten DeviceManagementConfiguration.Read.All. Detaljer: $($_.Exception.Message)"
    }
    $status = [string](Get-Prop $settings 'bindStatus')
    if ($status -notin @('bound', 'boundAndValidated')) {
        throw "Intune er ikke koblet til Managed Google Play (bindStatus: '$status'). Koble til under Devices > Enrollment > Android > Prerequisites > Managed Google Play i admin-senteret. Dette krever pålogging hos Google og kan ikke gjøres i script."
    }
    Write-Host ("Managed Google Play er koblet ({0}). Organisasjon: {1}. Siste appsynk: {2} ({3})." -f $status, (Get-Prop $settings 'ownerOrganizationName'), (Get-Prop $settings 'lastAppSyncDateTime'), (Get-Prop $settings 'lastAppSyncStatus'))
}

function Find-ManagedPlayApp {
    param([Parameter(Mandatory = $true)][string]$Package)
    return @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/mobileApps" |
            Where-Object { (Get-Prop $_ '@odata.type') -eq '#microsoft.graph.androidManagedStoreApp' -and (Get-Prop $_ 'packageId') -eq $Package })
}

function Get-OrApproveManagedPlayApp {
    $apps = @(Find-ManagedPlayApp -Package $PackageId)
    if ($apps.Count -gt 1) {
        throw "Fant flere Managed Google Play-apper med pakkenavn $PackageId. Bruk -AppId for å velge riktig."
    }
    if ($apps.Count -eq 1) {
        Write-Host "Fant Managed Google Play-appen '$(Get-Prop $apps[0] 'displayName')' ($(Get-Prop $apps[0] 'id'))."
        return $apps[0]
    }

    if (-not $ApproveAndSync) {
        throw "Appen $PackageId er ikke godkjent og synkronisert fra Managed Google Play ennå. Legg den til i admin-senteret: Apps > All Apps > Create > Managed Google Play app > søk etter appen > Select > Sync. Kjør deretter scriptet på nytt. Alternativt: -ApproveAndSync -ApproveAllPermissions."
    }
    if (-not $ApproveAllPermissions) {
        throw "-ApproveAndSync krever -ApproveAllPermissions, som bekrefter at organisasjonen godtar tillatelsene appen ber om. Se over tillatelsene i Google Play først."
    }

    if (-not $PSCmdlet.ShouldProcess($PackageId, 'Godkjenn i Managed Google Play (alle tillatelser) og synkroniser til Intune')) {
        Write-Host "WhatIf: ville godkjent $PackageId i Managed Google Play og startet synk."
        return $null
    }
    Write-Host "Godkjenner $PackageId i Managed Google Play..."
    Invoke-Graph -Method POST -Uri "$script:GraphBeta/deviceManagement/androidManagedStoreAccountEnterpriseSettings/approveApps" -Body @{ packageIds = @($PackageId); approveAllPermissions = $true } | Out-Null
    Write-Host "Starter synkronisering av Managed Google Play-apper..."
    Invoke-Graph -Method POST -Uri "$script:GraphBeta/deviceManagement/androidManagedStoreAccountEnterpriseSettings/syncApps" | Out-Null

    $deadline = (Get-Date).AddMinutes($SyncTimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 30
        $apps = @(Find-ManagedPlayApp -Package $PackageId)
        if ($apps.Count -ge 1) {
            Write-Host "Appen er synkronisert: '$(Get-Prop $apps[0] 'displayName')' ($(Get-Prop $apps[0] 'id'))."
            return $apps[0]
        }
        Write-Host "Venter på synk..."
    }
    throw "Appen $PackageId dukket ikke opp innen $SyncTimeoutMinutes minutter. Sjekk Apps > All Apps i admin-senteret, og kjør scriptet på nytt uten -ApproveAndSync."
}

function Get-ExistingAndroidApp {
    $app = Invoke-Graph -Uri "$script:GraphBeta/deviceAppManagement/mobileApps/$AppId"
    $type = [string](Get-Prop $app '@odata.type')
    if (-not $script:AndroidAppTypes.ContainsKey($type)) {
        throw "App $AppId er av typen $(if ($type) { $type } else { "ukjent" }), ikke en Android-app. Bruk riktig script for plattformen."
    }
    Write-Host "Fant '$(Get-Prop $app 'displayName')' ($($script:AndroidAppTypes[$type]))."
    switch ($type) {
        '#microsoft.graph.androidLobApp' {
            Write-Warning "Direkte LOB (.apk) virker bare på Android Enterprise fully managed og dedikerte enheter. Til work profile (BYOD/COPE): publiser appen som privat app i Managed Google Play."
        }
        '#microsoft.graph.androidStoreApp' {
            Write-Warning "Android store app er en vanlig Google Play-lenke og brukes ikke på Android Enterprise. Bruk Managed Google Play i stedet."
        }
    }
    return $app
}

function Add-MobileAppAssignment {
    <#
    .SYNOPSIS
        Legger til én gruppetildeling på appen uten å røre eksisterende tildelinger.
    #>
    param([Parameter(Mandatory = $true)]$App, [Parameter(Mandatory = $true)][string]$TargetGroupId)

    $id = [string](Get-Prop $App 'id')
    $intentValue = $Intent.ToLowerInvariant()
    $current = @(Get-GraphCollection -Uri "$script:GraphBeta/deviceAppManagement/mobileApps/$id/assignments")
    foreach ($a in $current) {
        if ((Get-Prop (Get-Prop $a 'target') 'groupId') -eq $TargetGroupId) {
            if ((Get-Prop $a 'intent') -eq $intentValue) {
                Write-Host "Gruppen har allerede tildelingen $Intent. Ingen endring."
                return
            }
            throw "Gruppen er allerede tildelt appen med intent '$(Get-Prop $a 'intent')'. Endre tildelingen i Intune manuelt hvis det er meningen."
        }
    }

    # Ingen innstillinger sendes. Oppdateringsprioritet og spor (track) for Managed Google
    # Play kan settes i admin-senteret på tildelingen ved behov.
    $body = [ordered]@{
        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
        intent        = $intentValue
        target        = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $TargetGroupId }
    }

    if (-not $PSCmdlet.ShouldProcess("$(Get-Prop $App 'displayName') ($id)", "Tildel $Intent til gruppe $TargetGroupId")) {
        Write-Host "WhatIf: ville tildelt $Intent til gruppe $TargetGroupId."
        return
    }
    Invoke-Graph -Method POST -Uri "$script:GraphBeta/deviceAppManagement/mobileApps/$id/assignments" -Body $body | Out-Null
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

$scopes = @('DeviceManagementApps.ReadWrite.All')
$scopes += if ($ApproveAndSync) { 'DeviceManagementConfiguration.ReadWrite.All' } else { 'DeviceManagementConfiguration.Read.All' }
if ($GroupName) { $scopes += 'Group.Read.All' }

Write-Host "Plattform: Android | metode: $($PSCmdlet.ParameterSetName) | intent: $Intent"
Import-GraphAuthenticationModule
Connect-IntuneGraph -Scopes $scopes

$app = $null
if ($PSCmdlet.ParameterSetName -eq 'ManagedGooglePlay') {
    Assert-ManagedGooglePlayBinding
    $app = Get-OrApproveManagedPlayApp
}
else {
    $type = $null
    $app = Get-ExistingAndroidApp
    $type = [string](Get-Prop $app '@odata.type')
    if ($type -in @('#microsoft.graph.androidManagedStoreApp', '#microsoft.graph.androidManagedStoreWebApp')) {
        Assert-ManagedGooglePlayBinding
    }
}

if ($SkipAssignment) {
    Write-Host "Tildeling hoppet over (-SkipAssignment)."
    return $app
}

$targetGroupId = Resolve-EntraGroupId -Id $GroupId -Name $GroupName
if (-not $app) {
    Write-Host "WhatIf: appen finnes ikke i Intune ennå, så tildeling til $targetGroupId ($Intent) vises bare som plan."
    return
}

Add-MobileAppAssignment -App $app -TargetGroupId $targetGroupId
Write-Host "Ferdig. På work profile installeres Required-apper i jobbprofilen uten at brukeren må godkjenne."
Write-Host "Følg status under Apps > All Apps > $(Get-Prop $app 'displayName') > Device install status."
return $app
