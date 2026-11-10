#Requires -Version 5.1
# UTF-8 med BOM, slik at æ/ø/å vises riktig også i Windows PowerShell 5.1.
<#
.SYNOPSIS
    Oppretter den standardiserte Entra ID-pilotgruppen for testing av Slack MSIX i Intune.

.DESCRIPTION
    Scriptet oppretter en tildelt sikkerhetsgruppe i Entra ID (tidligere Azure AD) som brukes
    som Intune-pilotmål for Slack MSIX. Gruppen opprettes bare hvis den ikke allerede finnes.
    Oppslaget skjer på både visningsnavn og e-postkallenavn, slik at vi unngår duplikater.

    Gruppenavnkonvensjon (fast, brukes likt i Intune, script, GitHub og Confluence):

        Pilot - <produkt> <teknologi> - <mål>

    For denne utrullingen er visningsnavnet derfor:

        Pilot - Slack MSIX - Enheter

    Betydning av hvert ledd:
      - Pilot: gruppen er bare for begrenset testing, ikke produksjon.
      - Slack: produktet som skal testes.
      - MSIX: pakkeformatet (Slack har pensjonert MSI). Dette skiller gruppen
        fra en ev. eldre MSI-pilot.
      - Enheter: medlemskapet skal være enheter, ikke brukere. Intune krever
        en enhetsgruppe når Slack MSIX tildeles som LOB-app i enhetskontekst.

    Tekniske navn som følger konvensjonen:
      - Visningsnavn (DisplayName): Pilot - Slack MSIX - Enheter
      - E-postkallenavn (MailNickname): Pilot-Slack-MSIX-Enheter
      - Gruppetype: sikkerhetsgruppe (ikke Microsoft 365-gruppe)
      - Medlemskap: tildelt (assigned), ikke dynamisk, slik at piloten styres bevisst

    Når gruppen finnes, skriver scriptet ut objekt-ID-en. Den brukes som
    -DeviceGroupId i New-IntuneSlackWindowsApp.ps1.

.PARAMETER DisplayName
    Overstyr visningsnavnet bare hvis konvensjonen evidensbasert må fravikes.
    Standard er det faste navnet "Pilot - Slack MSIX - Enheter".

.PARAMETER MailNickname
    E-postkallenavn uten mellomrom. Må være unikt i tenanten.
    Standard: Pilot-Slack-MSIX-Enheter.

.PARAMETER Description
    Beskrivelse som lagres på gruppen i Entra ID.

.PARAMETER TenantId
    Tenant-ID. Valgfri ved interaktiv pålogging, påkrevd sammen med sertifikat.

.PARAMETER ClientId
    App-registreringens program-ID ved app-only-pålogging med sertifikat.

.PARAMETER CertificateThumbprint
    Tommelavtrykk for sertifikatet i lokal sertifikatlager. App-only, uten hemmelighet.

.EXAMPLE
    .\New-EntraSlackMsixPilotGroup.ps1

.EXAMPLE
    .\New-EntraSlackMsixPilotGroup.ps1 -WhatIf

.EXAMPLE
    .\New-EntraSlackMsixPilotGroup.ps1 -TenantId '<tenant>' -ClientId '<app-id>' -CertificateThumbprint '<thumbprint>'

.NOTES
    Minste Graph-rettighet: Group.ReadWrite.All.
    Ikke bruk klienthemmelighet i scriptet. For automatisering: sertifikat.

    Etter at gruppen er opprettet, legg inn enhetene som skal være med i piloter.
    Ikke legg inn brukere hvis målet er Slack MSIX i enhetskontekst.

    Kilde til hvorfor dette må være en enhetsgruppe:
    https://learn.microsoft.com/en-us/intune/app-management/deployment/deploy-windows
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Pilot - Slack MSIX - Enheter',

    [ValidatePattern('^[A-Za-z0-9-]+$')]
    [string]$MailNickname = 'Pilot-Slack-MSIX-Enheter',

    [ValidateNotNullOrEmpty()]
    [string]$Description = 'Standardisert pilotgruppe for testing av Slack MSIX i Intune. Tildelt sikkerhetsgruppe for enheter (ikke brukere), fordi MSIX i enhetskontekst må tildeles en enhetsgruppe. Navnekonvensjon: Pilot - <produkt> <teknologi> - <mål>.',

    [string]$TenantId,

    [string]$ClientId,

    [string]$CertificateThumbprint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Minste rettighet for å lese og ev. opprette sikkerhetsgruppen.
$script:RequiredScopes = @('Group.ReadWrite.All')

function Install-GraphGroupModules {
    <#
    .SYNOPSIS
        Sikrer at Microsoft.Graph-modulene for pålogging og grupper er tilgjengelige.
    #>
    foreach ($name in @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups')) {
        if (-not (Get-Module -ListAvailable -Name $name)) {
            Write-Host "Installerer modulen $name i CurrentUser-omfang..."
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module -Name $name -Scope CurrentUser -Force -AllowClobber
        }
        Import-Module $name -ErrorAction Stop
    }
}

function Connect-EntraGraph {
    <#
    .SYNOPSIS
        Kobler til Microsoft Graph interaktivt, eller med app-sertifikat hvis det er angitt.
    #>
    $appOnly = @($TenantId, $ClientId, $CertificateThumbprint) | Where-Object { $_ }
    if ($appOnly.Count -gt 0 -and $appOnly.Count -lt 3) {
        throw "App-only-pålogging krever at -TenantId, -ClientId og -CertificateThumbprint brukes sammen. Ikke bruk klienthemmelighet."
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
        $hasScopes = ($script:RequiredScopes | Where-Object { $context.Scopes -contains $_ }).Count -eq $script:RequiredScopes.Count
    }

    if ($hasScopes) {
        Write-Host "Bruker eksisterende Graph-økt ($($context.TenantId))."
        return
    }

    Write-Host "Kobler til Microsoft Graph interaktivt med rettigheten: $($script:RequiredScopes -join ', ')."
    $connectParams = @{ Scopes = $script:RequiredScopes; NoWelcome = $true }
    if ($TenantId) { $connectParams.TenantId = $TenantId }
    if ($PSCmdlet.ShouldProcess('Microsoft Graph', 'Connect-MgGraph (interaktiv)')) {
        Connect-MgGraph @connectParams
    }
}

function Get-ExistingPilotGroup {
    <#
    .SYNOPSIS
        Finner gruppen på visningsnavn eller e-postkallenavn, slik at vi ikke lager duplikater.
    #>
    $safeName = $DisplayName.Replace("'", "''")
    $safeNick = $MailNickname.Replace("'", "''")

    # ConsistencyLevel/Count trengs ikke for disse enkle eq-filtrene.
    # Vanlig eq-filter er nok her; ConsistencyLevel eventual er ikke nødvendig.
    $byName = @(Get-MgGroup -Filter "displayName eq '$safeName'" -Property Id, DisplayName, MailNickname, SecurityEnabled, MailEnabled, Description, GroupTypes -ErrorAction Stop)
    $byNick = @(Get-MgGroup -Filter "mailNickname eq '$safeNick'" -Property Id, DisplayName, MailNickname, SecurityEnabled, MailEnabled, Description, GroupTypes -ErrorAction Stop)

    # Slå sammen treff og fjern duplikater på Id.
    $all = @($byName + $byNick) | Sort-Object Id -Unique
    return @($all)
}

function New-StandardPilotGroup {
    <#
    .SYNOPSIS
        Oppretter den tildelte sikkerhetsgruppen med fast visningsnavn og kallenavn.
    #>
    # MailEnabled må være false og SecurityEnabled true for en ren sikkerhetsgruppe.
    # GroupTypes settes tom, ellers kan det bli en Microsoft 365-gruppe.
    $params = @{
        DisplayName     = $DisplayName
        Description     = $Description
        MailEnabled     = $false
        SecurityEnabled = $true
        MailNickname    = $MailNickname
        GroupTypes      = @()
    }

    return New-MgGroup @params
}

function Write-GroupSummary {
    param(
        [Parameter(Mandatory = $true)]$Group,
        [Parameter(Mandatory = $true)][string]$Outcome
    )

    Write-Host ""
    Write-Host "Utfall: $Outcome"
    Write-Host "Visningsnavn : $($Group.DisplayName)"
    Write-Host "Kallenavn    : $($Group.MailNickname)"
    Write-Host "Objekt-ID    : $($Group.Id)"
    Write-Host "Bruk denne ID-en som -DeviceGroupId i New-IntuneSlackWindowsApp.ps1."
}

# -----------------------------------------------------------------------------
# Hovedflyt
# -----------------------------------------------------------------------------
Write-Host "Standard gruppenavn: $DisplayName"
Write-Host "Konvensjon: Pilot - <produkt> <teknologi> - <mål>"

Install-GraphGroupModules
Connect-EntraGraph

Write-Host "Sjekker om gruppen allerede finnes (visningsnavn eller kallenavn)..."
$existing = Get-ExistingPilotGroup

if ($existing.Count -eq 1) {
    Write-Host "Gruppen finnes allerede. Ingen ny gruppe blir opprettet."
    Write-GroupSummary -Group $existing[0] -Outcome 'Allerede eksisterende gruppe (ingen endring)'
    return $existing[0]
}

if ($existing.Count -gt 1) {
    $list = ($existing | ForEach-Object { "$($_.DisplayName) [$($_.Id), kallenavn $($_.MailNickname)]" }) -join '; '
    throw "Fant flere grupper som matcher visningsnavn eller kallenavn: $list. Rydd opp i Entra ID før du kjører scriptet på nytt, slik at standardnavnet bare peker på én gruppe."
}

if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Opprett Entra ID-sikkerhetsgruppe for Slack MSIX-pilot')) {
    Write-Host "WhatIf: ville opprettet sikkerhetsgruppen '$DisplayName' med kallenavn '$MailNickname'."
    return
}

Write-Host "Gruppen finnes ikke. Oppretter tildelt sikkerhetsgruppe..."
$group = New-StandardPilotGroup
Write-GroupSummary -Group $group -Outcome 'Ny gruppe opprettet'
Write-Host "Neste steg: legg inn pilot-enhetene i gruppen, og bruk objekt-ID-en i New-IntuneSlackWindowsApp.ps1."
return $group
