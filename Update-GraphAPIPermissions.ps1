<#
.SYNOPSIS
    Script written to update the Graph API permissions of an application
.EXAMPLE
    ./Update-GraphAPIPermissions.ps1 -ApplicationID "00000000-0000-0000-0000-000000000000" -PermissionsToAdd @("Mail.Send")
.NOTES
    Author: Padure Sergio
    Company: Raindrops.dev
    Last Edit: 2022-09-22
    Version 0.1 Initial functional code
    Mapping: https://docs.microsoft.com/en-us/powershell/microsoftgraph/azuread-msoline-cmdlet-map?view=graph-powershell-1.0
#>

#Requires -modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

#Handling parameters
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$ApplicationID,
    [Parameter(Mandatory=$false)]
    [string[]]$PermissionsToAdd = @("Mail.Send")
)

#Clearing the Screen
Clear-Host

$ErrorActionPreference = "Stop"

#Connect to Graph API
try {
    $null = Get-MgOrganization -ErrorAction Stop
} 
catch {
    Write-Host "You're not connected to Graph Api, please connect"
    Connect-MgGraph -ContextScope Process -Scopes "Directory.ReadWrite.All, AppRoleAssignment.ReadWrite.All"
}

#Preparing Basic Variables
# Microsoft Graph App ID (DON'T CHANGE)
$GraphAppId = "00000003-0000-0000-c000-000000000000"

#Getting the Application ID from the App Object ID
#$TargetAzureADApplication = (Get-AzureADServicePrincipal -ObjectId $AppObjectID)
$TargetMGApplication = Get-MgServicePrincipal -Filter "appId eq '$ApplicationID'"
$TargetMGApplication
Start-Sleep -Seconds 10


#Applying Permissions
foreach ($GraphAPIPermission in $PermissionsToAdd) {
    #Getting the Service Principal for the Graph API App
    $GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
    $GraphServicePrincipal
    #Getting the Application Role for the Graph API Permission
    $AppRole = $GraphServicePrincipal.AppRoles | Where-Object { $_.Value -eq $GraphAPIPermission -and $_.AllowedMemberTypes -contains "Application" }
    $AppRole
    #Assigning the Application Role to the Application
    $params = @{
        PrincipalId = $TargetMGApplication.Id
        ResourceId = $GraphServicePrincipal.Id
        AppRoleId = $AppRole.Id
    }
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $TargetMGApplication.Id -BodyParameter $params
}