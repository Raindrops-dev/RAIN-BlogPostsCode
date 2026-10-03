<#
.SYNOPSIS
    Script written to automatically update FsLogix with the latest version on AVD hosts
    Code based on https://github.com/srozemuller/Windows-Virtual-Desktop/blob/master/Application-Management/FSLogix/install-fslogix.ps1 and https://github.com/aaronparker/FSLogix/blob/main/Intune/Install-FslogixApps.ps1
    Attention: this script is specifically made for x64 machines, there is no support for x86 machines
.EXAMPLE
    ./Update-FsLogixClient.ps1
.NOTES
    Author: Padure Sergio
    Company: Raindrops.dev
    Last Edit: 2026-10-03
    Version 0.1 Initial functional code
    Version 0.2 Added parameters for working directory, logs directory and verbose preference. Implemented cleanup of files after install on suggestion (and code contribution) from @jonwbstr
    Version 0.3 Compare installed and installer build versions instead of the ZIP release name
#>
# Defining parameters
[CmdletBinding()]
Param(
    #Setting Verbose Preference to have the output of the Write-Verbose code
    [Parameter(Mandatory = $false)]
    [string]$VerbosePreference = "Continue", #Continue to view Verbose messages, SilentlyContinue to hide them
    # Setting the working directory for the script
    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory = "C:\temp\fslogixclient",
    # Setting the directory where the logs will be saved
    [Parameter(Mandatory = $false)]
    [string]$LogsDirectory = $PSScriptRoot
)

function ConvertTo-FsLogixBuildVersion {
    param([string]$Value, [string]$Source)

    # Release labels such as 25.02 are not comparable to installed build versions.
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw "Cannot read a four-part FSLogix build version from ${Source}: '$Value'."
    }
    try {
        $Version = [version]($Value.Trim())
        if ($Version -eq [version]'0.0.0.0') {
            throw 'The build version is zero.'
        }
        return $Version
    }
    catch {
        throw "Cannot read a valid FSLogix build version from ${Source}: '$Value'."
    }
}

function Get-FsLogixInstalledVersion {
    param([string[]]$RegistryPaths)

    $ExistingRegistryPaths = @($RegistryPaths | Where-Object { Test-Path -LiteralPath $_ })
    $Versions = @(foreach ($RegistryPath in $ExistingRegistryPaths) {
        Get-ChildItem -LiteralPath $RegistryPath | Get-ItemProperty |
        Where-Object { $_.DisplayName -match 'Microsoft FSLogix Apps' } |
        Select-Object -ExpandProperty 'DisplayVersion'
    }) | Sort-Object -Unique
    $Versions = @($Versions)
    if ($Versions.Count -eq 0) {
        throw "FSLogix Apps is not installed. This script updates an existing installation."
    }
    if ($Versions.Count -ne 1) {
        throw "There are multiple versions of FsLogix installed. Please ensure there is only one version installed before running this script!"
    }
    return ConvertTo-FsLogixBuildVersion -Value $Versions[0] -Source 'the registry'
}

function Get-FsLogixInstallerVersion {
    param([string]$InstallerPath)

    $ProductVersion = (Get-Item -LiteralPath $InstallerPath -ErrorAction Stop).VersionInfo.ProductVersion
    return ConvertTo-FsLogixBuildVersion -Value $ProductVersion -Source $InstallerPath
}

#Clearing the Screen
Clear-Host

#Setting Error Action preference to Stop to ensure the code stops in case of error
$ErrorActionPreference = "Stop"

#Preparing basic variables
$WDExists = Test-Path -Path $WorkingDirectory
#Starting processing
if (-not $WDExists) {
    New-Item -Path $WorkingDirectory -ItemType 'directory' -Force
}

#Starting logging
$dateandtime = Get-Date -Format "dd_MM_yyyy_HH-mm"
$ErrorActionPreference = "SilentlyContinue"
Stop-Transcript | out-null
#Continuing
$ErrorActionPreference = "Stop"
Start-Transcript -path "$LogsDirectory\Update-FsLogixClient-$dateandtime.log" -append
$ProgressPreference = 'SilentlyContinue'

try {
    # The ZIP filename is a release label, not necessarily the installed build version.
    $FsLogixDownloadURL = 'https://aka.ms/fslogix_download'
    $Response = [System.Net.HttpWebRequest]::Create($FsLogixDownloadURL).GetResponse()
    try {
        $FsLogixFinalDownloadURL = $Response.ResponseUri.AbsoluteUri
        $FsLogixDownloadFilename = [System.IO.Path]::GetFileName($Response.ResponseUri.LocalPath)
    }
    finally {
        $Response.Close()
    }
    $FsLogixDownloadFilenameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($FsLogixDownloadFilename)
    if ([string]::IsNullOrWhiteSpace($FsLogixDownloadFilenameWithoutExtension) -or [System.IO.Path]::GetExtension($FsLogixDownloadFilename) -ne '.zip') {
        throw 'The FSLogix download URL did not resolve to a ZIP archive.'
    }

    #Getting the current version of fslogix installed
    $RegPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    $InstalledFSLogixVersion = Get-FsLogixInstalledVersion -RegistryPaths $RegPaths

    # Download and extract before comparing: only the installer knows its build version.
    $InstallerOutputfile = "$WorkingDirectory\$FsLogixDownloadFilename"
    $ExtractionPath = "$WorkingDirectory\$FsLogixDownloadFilenameWithoutExtension"
    if (Test-Path -LiteralPath $InstallerOutputfile) {
        Write-Output "Installer archive already exists, not downloading it again."
    }
    else {
        Start-BitsTransfer -Source $FsLogixFinalDownloadURL -Destination $InstallerOutputfile -Priority High -TransferPolicy Always -ErrorAction Stop
    }
    # Also extract cached ZIPs so retries work if an earlier extraction was incomplete.
    if (Test-Path -LiteralPath $ExtractionPath) {
        Remove-Item -LiteralPath $ExtractionPath -Recurse -Force
    }
    Expand-Archive -LiteralPath $InstallerOutputfile -DestinationPath $ExtractionPath -Force -ErrorAction Stop
    $FsLogixInstallerPath = "$ExtractionPath\x64\Release\FSLogixAppsSetup.exe"
    if (-not (Test-Path -LiteralPath $FsLogixInstallerPath)) {
        throw "Installer doesn't exist, something failed. Exiting."
    }
    $FsLogixDownloadVersion = Get-FsLogixInstallerVersion -InstallerPath $FsLogixInstallerPath

    Write-Output "Installed version of FsLogix is $InstalledFSLogixVersion and downloaded build is $FsLogixDownloadVersion."
    if ($InstalledFSLogixVersion -lt $FsLogixDownloadVersion) {
        Write-Output "A newer build is available. Starting install."
        $InstallProcess = Start-Process -FilePath $FsLogixInstallerPath -ArgumentList "/quiet /norestart" -Wait -PassThru
        if ($InstallProcess.ExitCode -notin @(0, 3010)) {
            throw "FSLogix failed to install. Exit code: $($InstallProcess.ExitCode)."
        }
        $AfterInstallVersion = Get-FsLogixInstalledVersion -RegistryPaths $RegPaths
        Write-Output "Version after install is $AfterInstallVersion"
        if ($AfterInstallVersion -ne $FsLogixDownloadVersion) {
            throw "Version after install is not the same as the downloaded build. Something went wrong."
        }
        if ($InstallProcess.ExitCode -eq 3010) {
            Write-Warning "FSLogix was updated. A restart is required."
        }
    }
    elseif ($InstalledFSLogixVersion -gt $FsLogixDownloadVersion) {
        Write-Output "Installed version is newer than the downloaded build. Skipping downgrade."
    }
    else {
        Write-Output "Installed version matches the downloaded build. No update required."
    }

    # Keep files on failure for diagnosis. Successful checks and updates can be cleaned up.
    Remove-Item -LiteralPath $InstallerOutputfile -Force
    Remove-Item -LiteralPath $ExtractionPath -Recurse -Force
}
finally {
    Stop-Transcript
}
