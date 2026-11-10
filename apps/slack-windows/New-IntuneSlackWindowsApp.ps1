#Requires -Version 5.1
# UTF-8 med BOM, slik at æ/ø/å vises riktig også i Windows PowerShell 5.1.
<#
.SYNOPSIS
    Laster ned offisiell Slack MSIX og publiserer den som LOB-app i Microsoft Intune.

.DESCRIPTION
    Dette er det sikreste, offisielt støttede valget for Slack på Windows i Intune
    (sjekket 10. november 2026).

    Hvorfor MSIX som LOB-app i enhetskontekst, og ikke de andre metodene:

    * Slack pensjonerte både per-bruker-MSI og maskin-MSI 15. september 2025.
      Ny utrulling skal bruke MSIX. Ikke bruk gamle MSI-filer selv om du fortsatt
      finner dem liggende et sted.
    * SlackSetup.exe fra den vanlige nedlastingssiden er en per-bruker-installasjon.
      Den er feil verktøy for styrt virksomhetsutrulling.
    * Microsoft Store kan levere Slack, men dere styrer ikke pakken like presist.
      Slack peker selv på MSIX for utrulling i stor skala.
    * Win32-innpakning som kjører Add-AppxProvisionedPackage er et unntak, typisk
      når dere vil tvinge MSI-rydding og MSIX i én pakke. For nye og rene enheter
      er LOB MSIX enklere, støttet av både Slack og Intune, og lettere å vedlikeholde.
    * Intune LOB i enhetskontekst, tildelt Required til en enhetsgruppe, gir
      maskininstallasjon: appen blir tilgjengelig for eksisterende og nye brukere
      på enheten. Available + enhetskontekst er ikke tillatt. Brukergruppe +
      enhetskontekst feiler.

    Hvis enhetene allerede har gammel Slack-MSI, må den avinstalleres først
    (se Uninstall-LegacySlackMsi.ps1). MSIX installeres ikke oppå MSI.

    Scriptet gjør dette:
      1. Finner gjeldende offisiell MSIX-versjon og laster den ned (eller bruker -PackagePath).
      2. Leser identitet fra AppxManifest.xml i pakken.
      3. Kobler til Microsoft Graph med minste nødvendige rettighet.
      4. Oppretter en windowsUniversalAppX-app, krypterer pakken og laster den opp.
      5. Tildeler appen Required i enhetskontekst til angitt Entra-enhetsgruppe.

    Autentisering: interaktiv pålogging ved manuell kjøring, eller app-registrering
    med sertifikat for automatisering. Client secret skal ikke brukes i scriptet.

.PARAMETER DeviceGroupId
    Objekt-ID for Entra ID-enhetsgruppen som skal få appen. Må være en enhetsgruppe.

.PARAMETER DeviceGroupName
    Visningsnavn for gruppen hvis du ikke har ID. Krever rettigheten Group.Read.All.

.PARAMETER Architecture
    x64 (standard) eller arm64. De fleste Windows-klienter er x64.

.PARAMETER PackagePath
    Lokal sti til en allerede lastet ned Slack.msix. Hopper over nedlasting.

.PARAMETER DownloadDirectory
    Mappe for nedlastet MSIX. Standard er en midlertidig mappe under %TEMP%.

.PARAMETER DisplayName
    Visningsnavn i Intune. Standard: Slack.

.PARAMETER Assign
    Tildel appen etter opplasting. På som standard. Bruk -Assign:$false for bare å publisere.

.PARAMETER UpdateExisting
    Hvis en Slack MSIX-app med samme pakkeidentitet allerede finnes, last opp ny
    innholdsversjon til den i stedet for å lage en ny app.

.PARAMETER TenantId
    Tenant-ID. Valgfri ved interaktiv pålogging, påkrevd sammen med sertifikat.

.PARAMETER ClientId
    App-registreringens program-ID ved app-only-pålogging med sertifikat.

.PARAMETER CertificateThumbprint
    Tommelavtrykk for sertifikatet i lokal sertifikatlager. App-only, uten hemmelighet.

.PARAMETER InformationUrl
    Lenke til mer informasjon som vises på appen i Intune.

.EXAMPLE
    .\New-IntuneSlackWindowsApp.ps1 -DeviceGroupId '11111111-2222-3333-4444-555555555555'

.EXAMPLE
    .\New-IntuneSlackWindowsApp.ps1 -DeviceGroupName 'Intune-Windows-Enheter' -Architecture x64

.EXAMPLE
    .\New-IntuneSlackWindowsApp.ps1 -TenantId '<tenant>' -ClientId '<app-id>' -CertificateThumbprint '<thumbprint>' -DeviceGroupId '<gruppe-id>'

.EXAMPLE
    .\New-IntuneSlackWindowsApp.ps1 -DeviceGroupId '<gruppe-id>' -WhatIf

.NOTES
    Forutsetninger:
      - Windows 10/11 Pro, Enterprise eller Education på klientene (LOB støttes ikke på Home).
      - Intune-lisens i tenanten.
      - PowerShell 5.1 eller 7 på administrasjons-PC-en.
      - Graph-rettighet DeviceManagementApps.ReadWrite.All (pluss Group.Read.All ved gruppenavn).

    AppLocker: ferdigpakkede apper kan være blokkert som standard. Se Microsofts
    dokumentasjon for packaged apps og AppLocker hvis installasjonen feiler der.

    Automatiske oppdateringer: Slack-MSIX kan oppdatere seg selv. Dette styres med
    AutoUpdate i Slacks desktop app-konfigurasjon, ikke i dette scriptet.

    Kilder (sjekket 10. november 2026):
      https://slack.com/help/articles/212475728-Deploy-Slack-for-Windows
      https://slack.com/help/articles/4426294050451-Slack-feature-and-plan-retirements
      https://learn.microsoft.com/en-us/intune/app-management/deployment/deploy-windows
      https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-windowsuniversalappx?view=graph-rest-1.0
      https://slack.com/help/articles/11906214948755-Manage-desktop-app-configurations
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$DeviceGroupId,

    [ValidateNotNullOrEmpty()]
    [string]$DeviceGroupName,

    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64',

    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$PackagePath,

    [string]$DownloadDirectory,

    [string]$DisplayName = 'Slack',

    [bool]$Assign = $true,

    [switch]$UpdateExisting,

    [string]$TenantId,

    [string]$ClientId,

    [string]$CertificateThumbprint,

    [string]$InformationUrl = 'https://slack.com/help/articles/212475728-Deploy-Slack-for-Windows'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Graph v1.0 for oppretting og tildeling. Innholdopplasting bruker beta, slik den
# offisielle Intune-flyten for LOB-filer typisk gjør.
$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'

# Offisiell permalink fra Slacks hjelpeartikkel for virksomhetsutrulling.
# ?ddl=1-siden er HTML/JavaScript og gir ikke filen direkte, derfor finner
# scriptet gjeldende versjon via den stabile x64-nedlastingsompekingen og
# henter Slack.msix fra samme CDN-mappe. Ikke last ned SlackSetup.exe.
$script:SlackVersionProbeUri = 'https://slack.com/ssb/download-win64'
$script:SlackOfficialMsixPage = 'https://slack.com/help/articles/212475728-Deploy-Slack-for-Windows'
$script:SlackPublisher = 'Slack Technologies, LLC'
$script:SlackIdentityName = 'com.tinyspeck.slackdesktop'

# -----------------------------------------------------------------------------
# Hjelpefunksjoner
# -----------------------------------------------------------------------------
function Test-IsGuid {
    param([string]$Value)
    return $Value -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
}

function Install-GraphAuthenticationModule {
    if (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication) {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        return
    }

    Write-Host "Installerer modulen Microsoft.Graph.Authentication i CurrentUser-omfang..."
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}

function Connect-IntuneGraph {
    $scopes = @('DeviceManagementApps.ReadWrite.All')
    if ($DeviceGroupName) {
        $scopes += 'Group.Read.All'
    }

    if ($ClientId -and $CertificateThumbprint) {
        Write-Host "Kobler til Microsoft Graph med app-sertifikat (ingen klienthemmelighet)."
        if ($PSCmdlet.ShouldProcess('Microsoft Graph', 'Connect-MgGraph (sertifikat)')) {
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome
        }
        return
    }

    $context = $null
    try { $context = Get-MgContext } catch { $context = $null }

    $hasScopes = $false
    if ($context -and $context.Scopes) {
        $hasScopes = ($scopes | Where-Object { $context.Scopes -contains $_ }).Count -eq $scopes.Count
    }

    if ($hasScopes) {
        Write-Host "Bruker eksisterende Graph-økt ($($context.TenantId))."
        return
    }

    Write-Host "Kobler til Microsoft Graph interaktivt med rettighetene: $($scopes -join ', ')."
    $connectParams = @{ Scopes = $scopes; NoWelcome = $true }
    if ($TenantId) { $connectParams.TenantId = $TenantId }
    if ($PSCmdlet.ShouldProcess('Microsoft Graph', 'Connect-MgGraph (interaktiv)')) {
        Connect-MgGraph @connectParams
    }
}

function Invoke-GraphJson {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        $Body,
        [int]$TimeoutSec = 120
    )

    $params = @{ Method = $Method; Uri = $Uri }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        if ($Body -is [string]) {
            $params.Body = $Body
        }
        else {
            $params.Body = $Body | ConvertTo-Json -Depth 20 -Compress
        }
        $params.Headers = @{ 'Content-Type' = 'application/json' }
    }

    return Invoke-MgGraphRequest @params
}

function Resolve-DeviceGroupId {
    if ($DeviceGroupId) {
        return $DeviceGroupId
    }

    $safeName = $DeviceGroupName.Replace("'", "''")
    $uri = "$script:GraphV1/groups?`$filter=displayName eq '$safeName'&`$select=id,displayName,securityEnabled,groupTypes"

    $result = Invoke-GraphJson -Method GET -Uri $uri
    $groups = @($result.value)
    if ($groups.Count -eq 0) {
        throw "Fant ingen Entra-gruppe med visningsnavn '$DeviceGroupName'."
    }
    if ($groups.Count -gt 1) {
        $ids = ($groups | ForEach-Object { "$($_.displayName) ($($_.id))" }) -join ', '
        throw "Fant flere grupper med visningsnavn '$DeviceGroupName': $ids. Bruk -DeviceGroupId."
    }

    Write-Host "Fant gruppen '$($groups[0].displayName)' ($($groups[0].id))."
    Write-Host "Kontroller at dette er en enhetsgruppe. MSIX i enhetskontekst feiler hvis målet er en brukergruppe."
    return [string]$groups[0].id
}

function Get-CurrentSlackMsixUri {
    param([Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture)

    Write-Host "Finner gjeldende offisiell Slack-versjon via $script:SlackVersionProbeUri ..."

    # Vi følger bare ompekingen for å lese versjonsmappen, og laster aldri ned SlackSetup.exe.
    $request = [System.Net.HttpWebRequest]::Create($script:SlackVersionProbeUri)
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'IntuneSlackPublisher/1.0'
    $request.Timeout = 30000

    $response = $null
    try {
        $response = $request.GetResponse()
        $location = $response.Headers['Location']
        $status = [int]$response.StatusCode
    }
    catch [System.Net.WebException] {
        $response = $_.Exception.Response
        if (-not $response) { throw }
        $location = $response.Headers['Location']
        $status = [int]$response.StatusCode
    }
    finally {
        if ($response) { $response.Close() }
    }

    if (-not $location) {
        throw "Fikk ikke ompeking fra $script:SlackVersionProbeUri (HTTP $status). Last ned MSIX manuelt fra $script:SlackOfficialMsixPage og bruk -PackagePath."
    }

    # Forventet form: https://downloads.slack-edge.com/desktop-releases/windows/x64/<versjon>/SlackSetup.exe
    if ($location -notmatch 'desktop-releases/windows/(?<arch>x64|arm64)/(?<version>[^/]+)/') {
        throw "Uventet nedlastingsompeking: $location. Bruk -PackagePath og hent MSIX fra $script:SlackOfficialMsixPage."
    }

    $version = $Matches['version']
    $msixUri = "https://downloads.slack-edge.com/desktop-releases/windows/$Architecture/$version/Slack.msix"
    Write-Host "Gjeldende versjon ser ut til å være $version. MSIX-URL: $msixUri"
    return @{ Version = $version; Uri = $msixUri }
}

function Get-RemoteContentLength {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $true
    $request.UserAgent = 'IntuneSlackPublisher/1.0'
    $request.Timeout = 30000
    $response = $null
    try {
        $response = $request.GetResponse()
        return [int64]$response.ContentLength
    }
    finally {
        if ($response) { $response.Close() }
    }
}

function Save-SlackMsix {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $directory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Write-Host "Laster ned offisiell Slack MSIX til $Destination ..."
    # BITS er ikke alltid tilgjengelig; Invoke-WebRequest takler store filer (~170 MB) greit her.
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -UserAgent 'IntuneSlackPublisher/1.0'

    $item = Get-Item -LiteralPath $Destination
    if ($item.Length -lt 1MB) {
        throw "Nedlastet fil er uventet liten ($($item.Length) byte). Avbryter, slik at vi ikke laster opp feil innhold."
    }

    $hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    Write-Host ("Nedlasting ferdig. Størrelse={0:N0} byte, SHA256={1}" -f $item.Length, $hash)
    return $item
}

function Get-MsixPackageIdentity {
    param([Parameter(Mandatory = $true)][string]$SourceFile)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($SourceFile)
    try {
        $entry = $zip.Entries | Where-Object { $_.Name -eq 'AppxManifest.xml' } | Select-Object -First 1
        if (-not $entry) {
            throw "Fant ikke AppxManifest.xml i $SourceFile. Dette er ikke en gyldig MSIX/APPX-pakke."
        }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $xmlText = $reader.ReadToEnd() }
        finally { $reader.Close() }
    }
    finally {
        $zip.Dispose()
    }

    [xml]$manifest = $xmlText
    $identity = $manifest.Package.Identity
    if (-not $identity -or -not $identity.Name) {
        throw "Kunne ikke lese pakkeidentitet fra AppxManifest.xml."
    }

    $publisherHash = Get-MsixPublisherHash -Publisher $identity.Publisher
    $architecture = switch ("$($identity.ProcessorArchitecture)".ToLowerInvariant()) {
        'x64' { 'x64' }
        'x86' { 'x86' }
        'arm' { 'arm' }
        'arm64' { 'arm64' }
        default { 'neutral' }
    }

    $display = $manifest.Package.Properties.DisplayName
    $publisherDisplay = $manifest.Package.Properties.PublisherDisplayName

    return [pscustomobject]@{
        IdentityName                 = [string]$identity.Name
        IdentityVersion              = [string]$identity.Version
        IdentityPublisher            = [string]$identity.Publisher
        IdentityPublisherHash        = $publisherHash
        IdentityResourceIdentifier   = $(if ($identity.ResourceId) { [string]$identity.ResourceId } else { '' })
        ApplicableArchitectures      = $architecture
        DisplayName                  = $(if ($display) { [string]$display } else { [string]$identity.Name })
        PublisherDisplayName         = $(if ($publisherDisplay) { [string]$publisherDisplay } else { $script:SlackPublisher })
        PackageFamilyName            = "$($identity.Name)_$publisherHash"
    }
}

function Get-MsixPublisherHash {
    <#
    .SYNOPSIS
        Beregner publisher-hash som brukes i MSIX package family name og i Intune identityPublisherHash.
    #>
    param([Parameter(Mandatory = $true)][string]$Publisher)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        # Publisher-strengen hashes som UTF-16LE (Unicode).
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::Unicode.GetBytes($Publisher))
    }
    finally {
        $sha.Dispose()
    }

    $binary = -join ($hashBytes[0..7] | ForEach-Object { [System.Convert]::ToString($_, 2).PadLeft(8, '0') })
    $binary = $binary.PadRight(65, '0')
    $alphabet = '0123456789abcdefghjkmnpqrstvwxyz'
    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt 65; $i += 5) {
        $index = [System.Convert]::ToInt32($binary.Substring($i, 5), 2)
        [void]$builder.Append($alphabet[$index])
    }
    return $builder.ToString()
}

function Find-ExistingSlackApp {
    param([Parameter(Mandatory = $true)]$Identity)

    # Prøv å hente identitetsfeltene i listen. Faller tilbake til fullt oppslag bare når de mangler.
    $uri = "$script:GraphV1/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.windowsUniversalAppX')&`$select=id,displayName,publisher,fileName,identityName,identityPublisherHash,identityVersion"
    $matches = @()

    try {
        $pageProbe = Invoke-GraphJson -Method GET -Uri $uri
        $pages = @($pageProbe)
        $next = $pageProbe.'@odata.nextLink'
        while ($next) {
            $more = Invoke-GraphJson -Method GET -Uri $next
            $pages += $more
            $next = $more.'@odata.nextLink'
        }
    }
    catch {
        Write-Warning "Kunne ikke filtrere på windowsUniversalAppX i v1.0. Søker på visningsnavn i stedet. $($_.Exception.Message)"
        $fallback = "$script:GraphV1/deviceAppManagement/mobileApps?`$filter=displayName eq '$DisplayName'"
        $pages = @(Invoke-GraphJson -Method GET -Uri $fallback)
    }

    foreach ($page in $pages) {
        foreach ($app in @($page.value)) {
            $candidate = $app
            if (-not $candidate.identityName) {
                $candidate = Invoke-GraphJson -Method GET -Uri "$script:GraphV1/deviceAppManagement/mobileApps/$($app.id)"
            }
            if ($candidate.identityName -eq $Identity.IdentityName -and $candidate.identityPublisherHash -eq $Identity.IdentityPublisherHash) {
                $matches += $candidate
            }
        }
    }

    return $matches
}

function New-AesKeyBytes {
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.GenerateKey()
        return $aes.Key
    }
    finally { $aes.Dispose() }
}

function New-AesIvBytes {
    $aes = [System.Security.Cryptography.Aes]::Create()
    try { return $aes.IV }
    finally { $aes.Dispose() }
}

function Protect-IntuneLobFile {
    <#
    .SYNOPSIS
        Krypterer en LOB-fil slik Intune forventer (AES, HMAC-SHA256, ProfileVersion1) og returnerer commit-objektet.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$TargetFile
    )

    $encryptionKey = New-AesKeyBytes
    $hmacKey = New-AesKeyBytes
    $iv = New-AesIvBytes

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = $hmacKey
    $hmacLength = [int]($hmac.HashSize / 8)
    $buffer = New-Object byte[] (4KB)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $targetStream = [System.IO.File]::Open($TargetFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        # Reserver plass til HMAC + IV i starten av den krypterte filen.
        $header = New-Object byte[] ($hmacLength + $iv.Length)
        $targetStream.Write($header, 0, $header.Length)

        $encryptor = $aes.CreateEncryptor($encryptionKey, $iv)
        $sourceStream = [System.IO.File]::Open($SourceFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($targetStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
        try {
            $targetStream = $null
            while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $cryptoStream.Write($buffer, 0, $read)
            }
            $cryptoStream.FlushFinalBlock()
        }
        finally {
            if ($cryptoStream) { $cryptoStream.Dispose() }
            if ($sourceStream) { $sourceStream.Dispose() }
            if ($encryptor) { $encryptor.Dispose() }
        }
    }
    finally {
        if ($targetStream) { $targetStream.Dispose() }
        $aes.Dispose()
    }

    $finalStream = [System.IO.File]::Open($TargetFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
    try {
        $finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) | Out-Null
        $finalStream.Write($iv, 0, $iv.Length)
        $finalStream.Seek($hmacLength, [System.IO.SeekOrigin]::Begin) | Out-Null
        $mac = $hmac.ComputeHash($finalStream)
        $finalStream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
        $finalStream.Write($mac, 0, $mac.Length)
    }
    finally {
        $finalStream.Dispose()
        $hmac.Dispose()
    }

    $digestHex = (Get-FileHash -LiteralPath $SourceFile -Algorithm SHA256).Hash
    $digestBytes = New-Object byte[] ($digestHex.Length / 2)
    for ($i = 0; $i -lt $digestHex.Length; $i += 2) {
        $digestBytes[$i / 2] = [Convert]::ToByte($digestHex.Substring($i, 2), 16)
    }

    return @{
        fileEncryptionInfo = @{
            encryptionKey         = [Convert]::ToBase64String($encryptionKey)
            macKey                = [Convert]::ToBase64String($hmacKey)
            initializationVector  = [Convert]::ToBase64String($iv)
            mac                   = [Convert]::ToBase64String($mac)
            profileIdentifier     = 'ProfileVersion1'
            fileDigest            = [Convert]::ToBase64String($digestBytes)
            fileDigestAlgorithm   = 'SHA256'
        }
    }
}

function Send-AzureStorageChunks {
    param(
        [Parameter(Mandatory = $true)][string]$SasUri,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [int]$BlockSizeMb = 4
    )

    $chunkSize = 1MB * $BlockSizeMb
    $stream = [System.IO.File]::OpenRead($FilePath)
    $ids = @()
    $chunk = 0
    $total = [Math]::Ceiling($stream.Length / [double]$chunkSize)
    try {
        while ($stream.Position -lt $stream.Length) {
            $id = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($chunk.ToString('0000')))
            $ids += $id
            $size = [Math]::Min($chunkSize, $stream.Length - $stream.Position)
            $body = New-Object byte[] $size
            $null = $stream.Read($body, 0, $size)
            $chunk++
            Write-Progress -Activity 'Laster opp kryptert pakke til Intune-lager' -Status "Del $chunk av $total" -PercentComplete (($chunk / $total) * 100)
            Invoke-WebRequest -Uri "$SasUri&comp=block&blockid=$id" -Method Put -Body $body -Headers @{
                'x-ms-blob-type' = 'BlockBlob'
                'Content-Type'   = 'application/octet-stream'
            } -UseBasicParsing | Out-Null
        }
    }
    finally {
        $stream.Close()
        Write-Progress -Activity 'Laster opp kryptert pakke til Intune-lager' -Completed
    }

    $xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>' + (($ids | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
    Invoke-WebRequest -Uri "$SasUri&comp=blocklist" -Method Put -Body $xml -ContentType 'application/xml' -UseBasicParsing | Out-Null
}

function Wait-IntuneFileState {
    param(
        [Parameter(Mandatory = $true)][string]$FileUri,
        [Parameter(Mandatory = $true)][string]$Stage,
        [int]$Attempts = 60
    )

    $success = "${Stage}Success"
    $pending = "${Stage}Pending"
    for ($i = 0; $i -lt $Attempts; $i++) {
        $file = Invoke-GraphJson -Method GET -Uri $FileUri
        if ($file.uploadState -eq $success) { return $file }
        if ($file.uploadState -ne $pending) {
            throw "Opplastingsstatus ble '$($file.uploadState)' (forventet $pending eller $success)."
        }
        Start-Sleep -Seconds 2
    }
    throw "Tidsavbrudd mens filen ventet på status $success."
}

function Publish-WindowsUniversalAppX {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)]$Identity,
        [string]$ExistingAppId
    )

    $fileName = [IO.Path]::GetFileName($SourceFile)
    $tempFile = Join-Path ([IO.Path]::GetDirectoryName($SourceFile)) ("{0}_{1}_enc.bin" -f [IO.Path]::GetFileNameWithoutExtension($SourceFile), [guid]::NewGuid())

    $appBody = @{
        '@odata.type'                  = '#microsoft.graph.windowsUniversalAppX'
        displayName                    = $DisplayName
        publisher                      = $Identity.PublisherDisplayName
        description                    = 'Offisiell Slack MSIX, utdelt som Intune LOB-app i enhetskontekst. MSI er pensjonert og skal ikke brukes.'
        developer                      = $script:SlackPublisher
        owner                          = ''
        notes                          = 'Tildel Required til en enhetsgruppe med useDeviceContext=true. Avinstaller utgått MSI først hvis den finnes. Se Uninstall-LegacySlackMsi.ps1.'
        isFeatured                     = $false
        informationUrl                 = $InformationUrl
        privacyInformationUrl          = 'https://slack.com/trust/privacy/privacy-policy'
        fileName                       = $fileName
        applicableArchitectures        = $Identity.ApplicableArchitectures
        applicableDeviceTypes          = 'desktop'
        identityName                   = $Identity.IdentityName
        identityPublisherHash          = $Identity.IdentityPublisherHash
        identityResourceIdentifier     = $Identity.IdentityResourceIdentifier
        identityVersion                = $Identity.IdentityVersion
        isBundle                       = $false
        minimumSupportedOperatingSystem = @{
            '@odata.type' = '#microsoft.graph.windowsMinimumOperatingSystem'
            v10_0         = $true
        }
    }

    try {
        if ($ExistingAppId) {
            $appId = $ExistingAppId
            Write-Host "Oppdaterer eksisterende app $appId med ny innholdsversjon $($Identity.IdentityVersion)..."
        }
        else {
            Write-Host "Oppretter windowsUniversalAppX-appen '$DisplayName' i Intune..."
            $app = Invoke-GraphJson -Method POST -Uri "$script:GraphV1/deviceAppManagement/mobileApps" -Body $appBody
            $appId = [string]$app.id
            Write-Host "App opprettet: $appId"
        }

        Write-Host "Oppretter innholdsversjon og krypterer pakken før opplasting..."
        $content = Invoke-GraphJson -Method POST -Uri "$script:GraphBeta/deviceAppManagement/mobileApps/$appId/microsoft.graph.windowsUniversalAppX/contentVersions" -Body @{}
        $contentId = [string]$content.id

        $encryption = Protect-IntuneLobFile -SourceFile $SourceFile -TargetFile $tempFile
        $fileBody = @{
            '@odata.type'  = '#microsoft.graph.mobileAppContentFile'
            name           = $fileName
            size           = [int64](Get-Item -LiteralPath $SourceFile).Length
            sizeEncrypted  = [int64](Get-Item -LiteralPath $tempFile).Length
            manifest       = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($fileName))
            isDependency   = $false
        }

        $contentFile = Invoke-GraphJson -Method POST -Uri "$script:GraphBeta/deviceAppManagement/mobileApps/$appId/microsoft.graph.windowsUniversalAppX/contentVersions/$contentId/files" -Body $fileBody
        $fileId = [string]$contentFile.id
        $fileUri = "$script:GraphBeta/deviceAppManagement/mobileApps/$appId/microsoft.graph.windowsUniversalAppX/contentVersions/$contentId/files/$fileId"

        $file = Wait-IntuneFileState -FileUri $fileUri -Stage 'AzureStorageUriRequest'
        Write-Host "Laster opp kryptert pakke..."
        Send-AzureStorageChunks -SasUri $file.azureStorageUri -FilePath $tempFile

        Start-Sleep -Seconds 3
        Write-Host "Bekrefter filen i Intune..."
        Invoke-GraphJson -Method POST -Uri "$fileUri/commit" -Body $encryption
        $null = Wait-IntuneFileState -FileUri $fileUri -Stage 'CommitFile'

        Invoke-GraphJson -Method PATCH -Uri "$script:GraphV1/deviceAppManagement/mobileApps/$appId" -Body @{
            '@odata.type'            = '#microsoft.graph.windowsUniversalAppX'
            committedContentVersion  = $contentId
        }

        Write-Host "Innholdet er publisert (content version $contentId)."
        return $appId
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Set-SlackAppAssignment {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$GroupId
    )

    # POST til /assignments legger til én tildeling og overskriver ikke andre grupper.
    # (POST til /assign med hele samlingen ville erstattet alle eksisterende tildelinger.)
    $existing = Invoke-GraphJson -Method GET -Uri "$script:GraphV1/deviceAppManagement/mobileApps/$AppId/assignments"
    foreach ($row in @($existing.value)) {
        if ($row.target.groupId -eq $GroupId) {
            Write-Host "Gruppen $GroupId er allerede tildelt appen (intent=$($row.intent)). Lar den stå."
            return
        }
    }

    Write-Host "Tildeler appen Required i enhetskontekst til gruppe $GroupId ..."
    $body = @{
        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
        intent        = 'required'
        target        = @{
            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
            groupId       = $GroupId
        }
        settings      = @{
            '@odata.type'    = '#microsoft.graph.windowsUniversalAppXAppAssignmentSettings'
            useDeviceContext = $true
        }
    }

    Invoke-GraphJson -Method POST -Uri "$script:GraphV1/deviceAppManagement/mobileApps/$AppId/assignments" -Body $body
    Write-Host "Tildeling er lagret. Installasjonsstatus vises i Intune under appen når klientene har sjekket inn."
}

# -----------------------------------------------------------------------------
# Hovedflyt
# -----------------------------------------------------------------------------
$cleanupDownload = $false
$packageFile = $null

try {
    if ($Assign -and -not $DeviceGroupId -and -not $DeviceGroupName) {
        throw "Ved tildeling må du angi -DeviceGroupId eller -DeviceGroupName. Bruk -Assign:`$false for bare å publisere appen."
    }
    $appOnly = @($TenantId, $ClientId, $CertificateThumbprint) | Where-Object { $_ }
    if ($appOnly.Count -gt 0 -and $appOnly.Count -lt 3) {
        throw "App-only-pålogging krever at -TenantId, -ClientId og -CertificateThumbprint brukes sammen. Ikke bruk klienthemmelighet."
    }

    Write-Host "Anbefalt metode: offisiell Slack MSIX som Intune LOB-app i enhetskontekst."
    Write-Host "Dokumentasjon: $script:SlackOfficialMsixPage"

    if ($PackagePath) {
        $packageFile = (Resolve-Path -LiteralPath $PackagePath).Path
        Write-Host "Bruker lokal pakke: $packageFile"
    }
    else {
        $downloadInfo = Get-CurrentSlackMsixUri -Architecture $Architecture
        try {
            $null = Get-RemoteContentLength -Uri $downloadInfo.Uri
        }
        catch {
            throw "MSIX-filen ble ikke funnet på $($downloadInfo.Uri). Hent pakken fra $script:SlackOfficialMsixPage og kjør på nytt med -PackagePath. $($_.Exception.Message)"
        }

        if (-not $DownloadDirectory) {
            $DownloadDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("SlackMsix-" + [guid]::NewGuid())
            $cleanupDownload = $true
        }
        $packageFile = Join-Path $DownloadDirectory "Slack-$Architecture-$($downloadInfo.Version).msix"
        if ($PSCmdlet.ShouldProcess($downloadInfo.Uri, "Last ned Slack MSIX")) {
            $null = Save-SlackMsix -Uri $downloadInfo.Uri -Destination $packageFile
        }
        else {
            Write-Host "WhatIf: ville lastet ned $($downloadInfo.Uri) til $packageFile"
            return
        }
    }

    $identity = Get-MsixPackageIdentity -SourceFile $packageFile
    Write-Host "Pakkeidentitet: $($identity.IdentityName) $($identity.IdentityVersion) ($($identity.ApplicableArchitectures)), family $($identity.PackageFamilyName)"

    if ($identity.IdentityName -ne $script:SlackIdentityName) {
        throw "Pakken ser ikke ut til å være offisiell Slack (fant '$($identity.IdentityName)', forventet '$script:SlackIdentityName'). Avbryter."
    }

    Install-GraphAuthenticationModule
    Connect-IntuneGraph

    $groupId = $null
    if ($Assign) {
        $groupId = Resolve-DeviceGroupId
    }
    $existing = @()
    if (-not $WhatIfPreference) {
        $existing = @(Find-ExistingSlackApp -Identity $identity)
    }

    $existingAppId = $null
    if ($existing.Count -gt 0) {
        $existingAppId = [string]$existing[0].id
        $names = ($existing | ForEach-Object { "$($_.displayName) [$($_.id), versjon $($_.identityVersion)]" }) -join '; '
        if ($UpdateExisting) {
            if ($existing.Count -gt 1) {
                throw "Fant flere Slack MSIX-apper ($names). Angi hvilken som skal oppdateres ved å rydde duplikater først, eller fjern -UpdateExisting."
            }
            Write-Host "Oppdaterer eksisterende app: $names"
        }
        else {
            throw "Det finnes allerede en Slack MSIX-app i Intune: $names. Kjør med -UpdateExisting for å laste opp ny versjon, eller slett duplikatet i Intune først."
        }
    }

    $target = if ($existingAppId) { "Oppdater app $existingAppId" } else { 'Opprett ny Slack LOB-app' }
    if (-not $PSCmdlet.ShouldProcess("Intune tenant", $target)) {
        Write-Host "WhatIf: ville publisert $packageFile og tildele Required i enhetskontekst til $groupId."
        return
    }

    $appId = Publish-WindowsUniversalAppX -SourceFile $packageFile -Identity $identity -ExistingAppId $existingAppId

    if ($Assign) {
        Set-SlackAppAssignment -AppId $appId -GroupId $groupId
    }
    else {
        Write-Host "Hoppet over tildeling (-Assign:`$false). Tildel selv Required til en enhetsgruppe, med enhetskontekst på."
    }

    Write-Host ""
    Write-Host "Ferdig. App-ID: $appId"
    Write-Host "Husk: hvis maskinene har gammel Slack-MSI, utrull Uninstall-LegacySlackMsi.ps1 først."
    Write-Host "Portal: https://intune.microsoft.com/"
}
finally {
    if ($cleanupDownload -and $DownloadDirectory -and (Test-Path -LiteralPath $DownloadDirectory)) {
        Remove-Item -LiteralPath $DownloadDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
