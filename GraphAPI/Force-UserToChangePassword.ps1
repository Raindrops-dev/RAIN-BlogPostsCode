cls

Connect-MgGraph -Scopes Directory.AccessAsUser.All, Directory.ReadWrite.All, User.ReadWrite.All
#Select-MgProfile Beta


$UserUPN = "user@contoso.com"
$UserID = (Get-MgUser -UserId $UserUPN -ErrorAction Stop) | Select-Object -ExpandProperty 'Id'

$passwordprofile = @{}
#$passwordprofile["Password"] = "RqAXsU3N@JgDdVhMACXRtvHESih2mvr"
$passwordprofile["forceChangePasswordNextSignIn"] = $True
$passwordprofile["forceChangePasswordNextSignInWithMfa"] = $True

Write-Output "Getting the current password profile..."
$CurrentPasswordProfile = Get-MgUser -UserId $UserID -Property * | Select-Object -ExpandProperty 'PasswordProfile' | Format-List
$CurrentPasswordProfile

Write-Output "Updating the password profile..."
Update-MgUser -UserId $UserID -PasswordProfile $passwordprofile

Write-Output "Getting the updated password profile..."
$CurrentPasswordProfile = Get-MgUser -UserId $UserID -Property * | Select-Object -ExpandProperty 'PasswordProfile' | Format-List
$CurrentPasswordProfile

$null = Revoke-MgUserSignInSession -UserId $UserID