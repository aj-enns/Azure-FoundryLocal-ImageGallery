#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs Azure Foundry Local on Windows 11.
.DESCRIPTION
    Downloads and installs Azure Foundry Local using the Windows Package Manager (winget).
    Designed for use as an Azure Image Builder customization step or standalone execution.
    Requires Windows 11 with winget available and must be run as Administrator.
.EXAMPLE
    .\install-foundry-local.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message"
}

Write-Log 'Starting Azure Foundry Local installation'

# Ensure TLS 1.2+ is used for all web requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Log OS information
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
Write-Log "OS: $($osInfo.Caption) (Build $($osInfo.BuildNumber))"

# ── Ensure winget is available ──────────────────────────────────────────────
Write-Log 'Checking for Windows Package Manager (winget)...'
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue

if (-not $wingetCmd) {
    Write-Log 'winget not found – attempting to register App Installer...' -Level 'WARN'

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe

        # Refresh PATH so the current session can find winget
        $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path    = "$machinePath;$userPath"

        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    } catch {
        Write-Log "App Installer registration failed: $_" -Level 'WARN'
    }
}

if (-not $wingetCmd) {
    throw 'winget is required but could not be found. Ensure App Installer is installed on Windows 11.'
}

Write-Log "winget located at: $($wingetCmd.Source)"

# ── Accept winget source agreements ─────────────────────────────────────────
Write-Log 'Refreshing winget sources...'
winget source update --disable-interactivity 2>&1 | ForEach-Object { Write-Log $_ }

# ── Install Azure Foundry Local ──────────────────────────────────────────────
Write-Log 'Installing Azure Foundry Local (package: Microsoft.FoundryLocal)...'

$process = Start-Process -FilePath 'winget' -ArgumentList @(
    'install',
    'Microsoft.FoundryLocal',
    '--accept-package-agreements',
    '--accept-source-agreements',
    '--silent',
    '--disable-interactivity'
) -Wait -PassThru -NoNewWindow

# Exit code -1978335189 (0x8A15002B) means the package is already installed – treat as success
if ($process.ExitCode -ne 0 -and $process.ExitCode -ne -1978335189) {
    throw "Foundry Local installation failed with winget exit code: $($process.ExitCode)"
}

Write-Log 'Azure Foundry Local installed successfully.'

# ── Verify installation ──────────────────────────────────────────────────────
Write-Log 'Verifying installation...'

# Refresh PATH to pick up the newly installed binary
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path    = "$machinePath;$userPath"

$foundryCmd = Get-Command foundry -ErrorAction SilentlyContinue
if ($foundryCmd) {
    Write-Log "foundry CLI located at: $($foundryCmd.Source)"
    try {
        $version = & foundry --version 2>&1
        Write-Log "Foundry Local version: $version"
    } catch {
        Write-Log 'Could not retrieve version – a restart may be required.' -Level 'WARN'
    }
} else {
    Write-Log 'foundry command not detected in PATH – a machine restart may be required.' -Level 'WARN'
}

Write-Log 'install-foundry-local.ps1 completed successfully.'
