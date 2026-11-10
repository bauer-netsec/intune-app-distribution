#Requires -Version 5.1
# UTF-8 med BOM, slik at æ/ø/å vises riktig også i Windows PowerShell 5.1.
<#
.SYNOPSIS
    Avinstallerer utgått Slack-MSI (per-bruker- eller maskininstallasjon) fra Windows.

.DESCRIPTION
    Slack pensjonerte MSI-installasjonene 15. september 2025. Offisiell MSIX kan ikke
    installeres oppå en eksisterende MSI — MSI må vekk først.

    Dette scriptet er ment som en egen Intune-utrulling i systemkontekst, tildelt
    Required til samme enhetsgruppe som Slack-MSIX, og ferdig før MSIX-appen.
    Det rører ikke Slack installert som MSIX/APPX (pakkenavn com.tinyspeck.slackdesktop).

    Kjør det ikke som innlogget bruker hvis målet er maskin-MSI; da skal Intune
    kjøre det som SYSTEM.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-LegacySlackMsi.ps1

.NOTES
    Anbefalt Intune-bruk:
      - App-type: Windows-app (Win32), installasjonskontekst System
      - Installasjonskommando: powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-LegacySlackMsi.ps1
      - Avslutningskoder: 0 = ferdig (eller ingenting å fjerne), 3010 = ferdig, omstart anbefalt
      - Gjenkjenning (eksempel): PowerShell som returnerer «ikke funnet» når ingen Slack-MSI
        ligger i avinstalleringsregisteret. Ikke gjenkjenn på MSIX-stien.

    Kilde: https://slack.com/help/articles/212475728-Deploy-Slack-for-Windows
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LegacySlackMsiApps {
    <#
    .SYNOPSIS
        Finner Slack som er registrert som Windows Installer (MSI) i maskinens avinstalleringsregister.
    #>
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -and
            $_.DisplayName -match '^(Slack|Slack Machine-Wide)(\s|$)' -and
            (
                ($_.UninstallString -and $_.UninstallString -match 'msiexec') -or
                $_.WindowsInstaller -eq 1
            )
        }
}

function Get-MsiProductCode {
    param([Parameter(Mandatory = $true)]$App)

    # Produktkoden er vanligvis nøkkelens navn, {GUID}.
    $keyName = $App.PSChildName
    if ($keyName -match '^\{[0-9A-Fa-f-]{36}\}$') {
        return $keyName
    }

    if ($App.UninstallString -match '\{[0-9A-Fa-f-]{36}\}') {
        return $Matches[0]
    }

    return $null
}

Write-Host "Søker etter utgått Slack-MSI i maskinens avinstalleringsregister..."

$apps = @(Get-LegacySlackMsiApps)
if ($apps.Count -eq 0) {
    Write-Host "Ingen Slack-MSI funnet. Ingenting å fjerne (avslutter 0)."
    exit 0
}

$rebootRequired = $false
$failed = @()

foreach ($app in $apps) {
    $productCode = Get-MsiProductCode -App $app
    $display = [string]$app.DisplayName
    $version = [string]$app.DisplayVersion

    if (-not $productCode) {
        $failed += "$display $version (fant ikke MSI-produktkode)"
        Write-Warning "Hopper over '$display' fordi produktkoden ikke ble funnet. UninstallString=$($app.UninstallString)"
        continue
    }

    $action = "Avinstaller $display $version ($productCode)"
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, $action)) {
        continue
    }

    Write-Host $action
    # /qn = stille, /norestart = la Intune styre eventuell omstart.
    $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/x', $productCode, '/qn', '/norestart') -Wait -PassThru
    $code = $process.ExitCode

    switch ($code) {
        { $_ -in 0, 1605 } {
            # 1605 = produktet er allerede borte. Behandles som suksess.
            Write-Host "Ferdig: $display (kode $code)"
        }
        { $_ -in 1641, 3010 } {
            Write-Host "Ferdig med omstartkode: $display (kode $code)"
            $rebootRequired = $true
        }
        default {
            $failed += "$display $version (msiexec $code)"
            Write-Warning "Avinstallasjon feilet for $display med kode $code"
        }
    }
}

if ($failed.Count -gt 0) {
    Write-Error ("Kunne ikke fjerne: " + ($failed -join '; '))
    exit 1603
}

if ($rebootRequired) {
    Write-Host "Avinstallasjon fullført. En omstart er anbefalt (avslutter 3010)."
    exit 3010
}

Write-Host "Avinstallasjon fullført."
exit 0
