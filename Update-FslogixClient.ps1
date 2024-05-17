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
    Last Edit: 2022-09-18
    Version 0.1 Initial functional code
#>

#Clearing the Screen
Clear-Host

#Setting Error Action preference to Stop to ensure the code stops in case of error
$ErrorActionPreference = "Stop"

#Setting Verbose Preference to have the output of the Write-Verbose code
$VerbosePreference = "Continue"

#Preparing basic variables
$WorkingDirectory = "C:\temp\fslogixclient"
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
$ErrorActionPreference = "Continue"
Start-Transcript -path "$PSScriptRoot\Update-FsLogixClient-$dateandtime.log" -append
$ProgressPreference = 'SilentlyContinue' 

#Starting processing
#Getting the final URL, Output filename of the latest version of fslogix and then the version itself
$FsLogixDownloadURL = 'https://aka.ms/fslogix_download'
$FsLogixFinalDownloadURL = [System.Net.HttpWebRequest]::Create($FsLogixDownloadURL).GetResponse().ResponseUri.AbsoluteUri
$FsLogixDownloadFilename = $FsLogixFinalDownloadURL.split("/")[-1]
$FsLogixDownloadFilenameWithoutExtension = $FsLogixDownloadFilename.SubString(0, $FsLogixDownloadFilename.LastIndexOf('.'))
$FsLogixDownloadVersion0 = $FsLogixDownloadFilename.split("_")[-1]
$FsLogixDownloadVersion = $FsLogixDownloadVersion0.SubString(0, $FsLogixDownloadVersion0.LastIndexOf('.'))

#Getting the current version of fslogix installed
$RegPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
$InstalledFSLogixVersion = Get-ChildItem -Path $RegPaths | Get-ItemProperty | Where-Object { $_.DisplayName -match 'Microsoft FSLogix Apps' } | Select-Object -ExpandProperty 'DisplayVersion' | Get-Unique
$versiontype = $InstalledFSLogixVersion.GetType().Name
if ($versiontype -ne "String") {
    throw "There are multiple versions of FsLogix installed. Please ensure there is only one version installed before running this script!"
}

#Checking if the installed version is the latest
Write-Output "Installed version of FsLogix is $InstalledFSLogixVersion and newest is $FsLogixDownloadVersion."
if ($InstalledFSLogixVersion -ne $FsLogixDownloadVersion) {
    Write-Output "Installed version is not the latest version. Downloading and installing latest version"
    $InstallerOutputfile = "$WorkingDirectory\$FsLogixDownloadFilename"
    try {
        $InstallerExists = Test-Path -Path $InstallerOutputfile
        if ($InstallerExists) {
            Write-Output "Installer already exists, not gonna redownload"
        }
        else {
            #Invoke-WebRequest $FsLogixFinalDownloadURL -OutFile $InstallerOutputfile
            Start-BitsTransfer -Source $FsLogixFinalDownloadURL -Destination $InstallerOutputfile -Priority High -TransferPolicy Always -ErrorAction Continue -ErrorVariable $ErrorBits
            Expand-Archive -LiteralPath $InstallerOutputfile -DestinationPath "$WorkingDirectory\$FsLogixDownloadFilenameWithoutExtension"
        }
        Write-Output "Checking if required installer is present"
        $FsLogixInstallerPath = "$WorkingDirectory\$FsLogixDownloadFilenameWithoutExtension\x64\Release\FSLogixAppsSetup.exe"
        $FsLogixInstallerExists = Test-Path $FsLogixInstallerPath
        if ($FsLogixInstallerExists) {
            Write-Output "$FsLogixInstallerPath exists. Starting Install"
            try {
                Start-Process -FilePath $FsLogixInstallerPath -ArgumentList "/quiet /norestart" -Wait
                Write-Output "Update Completed. Checking the current version in the registry."
                $AfterInstallVersion = Get-ChildItem -Path $RegPaths | Get-ItemProperty | Where-Object { $_.DisplayName -match 'Microsoft FSLogix Apps' } | Select-Object -ExpandProperty 'DisplayVersion' | Get-Unique
                Write-Output "Version after install is $AfterInstallVersion"
                Write-Output "Cleaning up installer files"
                Remove-Item -Force $InstallerOutputfile
                Remove-Item -Force -Recurse "$WorkingDirectory\$FsLogixDownloadFilenameWithoutExtension"
            }
            catch {
                throw "FSLogix failed to install $_"
            }
        }
        else {
            throw "Installer doesn't exist, something failed. Exiting."
        }
    }
    catch {
        Write-Warning "Something went wrong with either the download or the expansion"
        throw $_
    }
}
else {
    Write-Output "Installed version is the latest. Exiting."
}


#Stop logging
Stop-Transcript
