cls

Connect-MgGraph -Scopes Directory.AccessAsUser.All, Directory.ReadWrite.All, User.ReadWrite.All
#Select-MgProfile Beta

$UsersToChangePassword = Get-MgUser -All -Property UserPrincipalName, Id

$CSVOutput = @()

foreach ($UserToChangePassword in $UsersToChangePassword) {
    #Preparing variables
    $UserUPN = $UserToChangePassword.UserPrincipalName
    $UserID = $UserToChangePassword.Id

    #Defining the Password Profile
    $passwordprofile = @{}
    $passwordprofile["forceChangePasswordNextSignIn"] = $True
    $passwordprofile["forceChangePasswordNextSignInWithMfa"] = $True
    
    Write-Output "Getting the current password profile for user $UserUPN..."
    $CurrentPasswordProfile = Get-MgUser -UserId $UserID -Property * | Select-Object -ExpandProperty 'PasswordProfile' | Format-List
    $CurrentPasswordProfile
    
    Write-Output "Updating the password profile for user $UserUPN..."
    try {
        Update-MgUser -UserId $UserID -PasswordProfile $passwordprofile -ErrorAction Stop
        Write-Output "Password profile updated successfully for user $UserUPN..."
    }
    catch {
        Write-Output "Password profile update failed for user $UserUPN..."
        Write-Warning $_.Exception.Message
    }  
    
    Write-Output "Getting the updated password profile for user $UserUPN..."
    $CurrentPasswordProfile = Get-MgUser -UserId $UserID -Property * | Select-Object -ExpandProperty 'PasswordProfile' | Format-List
    $CurrentPasswordProfile

}