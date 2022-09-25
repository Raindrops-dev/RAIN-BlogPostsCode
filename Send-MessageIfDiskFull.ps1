<#
.SYNOPSIS
    Script written to send an email if a disk is full
.EXAMPLE
    ./Send-MessageIfDiskFull.ps1
.NOTES
    Author: Padure Sergio
    Company: Raindrops.dev
    Last Edit: 2022-09-22
    Version 0.1 Initial functional code
#>

#Requires -PSEdition Desktop

#Clearing the Screen
Clear-Host

#Setting Error Action preference to Stop to ensure the code stops in case of error
$ErrorActionPreference = "Stop"

#Setting Verbose Preference to have the output of the Write-Verbose code
$VerbosePreference = "Continue"

#Preparing basic variables
$RootDir = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
$ConfigFile = Get-Content -Path "$RootDir\EmailConfig.json" | ConvertFrom-Json
$datetime = Get-Date -Format "yyyy_MM_dd_HH_mm"
$AppId = $ConfigFile.AppID
$AppSecret = $ConfigFile.AppSecret
$EmailSender = $ConfigFile.EmailSender
$EmailReceiver = $ConfigFile.EmailReceiver
$tenantId = $ConfigFile.TenantID
$KeyVaultName = $ConfigFile.KeyVaultName
$KeyVaultSecretName = $ConfigFile.KeyVaultSecretName
$ComputerName = $env:COMPUTERNAME

#Getting the App Secret from keyvault through Managed Identity
Login-AzAccount -Identity
$AppSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecretName -AsPlainText

# Construct URI and body needed for authentication
$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$body = @{
    client_id     = $AppId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $AppSecret
    grant_type    = "client_credentials"
}

$tokenRequest = Invoke-WebRequest -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $body -UseBasicParsing
# Unpack Access Token
$token = ($tokenRequest.Content | ConvertFrom-Json).access_token

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-type"  = "application/json"
}

$EmailSubject = "Disk Full on $ComputerName"

#Getting the disk usage status
$drives = Get-PSDrive -PSProvider FileSystem
foreach ($drive in $drives) {
    $name = $drive.name
    $free = [int][math]::Round(($drive.free / ($drive.free + $drive.used) * 100))
    if ($free -lt 30) {
        Write-Warning "Disk $name is full: $free %, sending email"
        #Sending email if disk is full
        $MessageParams = @{
            "URI"         = "https://graph.microsoft.com/v1.0/users/$EmailSender/sendMail"
            "Headers"     = $Headers
            "Method"      = "POST"
            "ContentType" = 'application/json; charset=utf-8'
            "Body"        = (@{
                    "message" = @{
                        "subject"      = $EmailSubject
                        "body"         = @{
                            "contentType" = 'Text' 
                            "content"     = "The disk on $ComputerName is full. Disk free space is $free %. The disk is $name"
                        }
                        "toRecipients" = @(
                            @{
                                "emailAddress" = @{"address" = $EmailReceiver }
                            } ) 
        
                    }
                }) | ConvertTo-JSON -Depth 6
        }
        $tries = 0
        while ($tries -lt 5) {
            try {
                Write-Output "Sending mail to $EmailReceiver with title $EmailSubject"
                Invoke-RestMethod @Messageparams -ErrorAction Stop
                Start-Sleep -Seconds 1
                $tries = 5
            }
            catch {
                Write-Warning "Mail Send failed for $EmailReceiver. Trying again in 1 second. Error: $error[0]"
                Start-Sleep -Seconds 1
                $tries += 1
                if ($tries = 5) {
                    Write-Output "Failed Mail send for $EmailReceiver after 5 tries. Error: $error[0]"
                }
            }
        }
    }
}

