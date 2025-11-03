
#Requires -Modules ActiveDirectory, Microsoft.Graph

# Définition des variables globales
$exportUsersFile = "C:\Temp\AD_Users.csv"
$exportGroupsFile = "C:\Temp\AD_Groups.xlsx"
$logFile = "C:\Temp\ADMigration.log"
$global:logFile = "C:\Temp\ADMigration.log"


#region - Log writing function
function Log-Message {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$LogLevel = "INFO"
    )

    $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
    $logEntry = "$timestamp [$LogLevel] $Message"

    # Écriture dans le fichier log
    try {
        Add-Content -Path $global:logFile -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Host " Impossible d'écrire dans le fichier de log : $_" -ForegroundColor Red
    }

    # Couleur en fonction du niveau de log
    switch ($LogLevel.ToUpper()) {
        "SUCCESS" { $color = "Green" }
        "WARNING" { $color = "Yellow" }
        "ERROR"   { $color = "Red" }
        default   { $color = "White" }
    }

    # Affichage à l'écran
    Write-Host $logEntry -ForegroundColor $color
}

#endregion

#region - User export function with their attributes
function Export-ADUsers {
 param (
        [string]$OUPath # Exemple : "OU=Finance,OU=Utilisateurs,DC=contoso,DC=contoso,DC=local"
    )

    Log-Message "Exporting Active Directory users is in progress..." "INFO"
    
    

    $users = Get-ADUser -SearchBase $OUPath -Filter * -Properties * | Select-Object *

    $usersFormatted = $users | ForEach-Object {
        [PSCustomObject]@{
            UPN             = $_.UserPrincipalName
            Name            = $_.Name
            GivenName       = $_.GivenName
            Surname         = $_.SurName
            SamAccountName  = $_.SamAccountName
            EmailAddress    = $_.Mail
            Department      = $_.Department
            Title           = $_.Title
            DisplayName     = $_.DisplayName
            ProxyAddresses  = ($_.ProxyAddresses -join ", ")
            Office          = $_.Office
            TelephoneNumber = $_.TelephoneNumber
            StreetAddress   = $_.StreetAddress
            City            = $_.City
            State           = $_.State
            PostalCode      = $_.PostalCode
            Country         = $_.Country
            Description     = $_.Description
            FacsimileTelephoneNumber = $_.FacsimileTelephoneNumber
            Company         = $_.Company
            Manager         = $_.Manager
            
        }
    }

    $usersFormatted | Export-CSV -Path $exportUsersFile -NotypeInformation -Encoding UTF8 -delimiter ","
    Log-Message "Export completed: $exportUsersFile" "SUCCESS"
}

#endregion

#region - Security group export function
function Export-ADGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OUPath, # Exemple : "OU=Finance,OU=Utilisateurs,DC=contoso,DC=local"

        [Parameter(Mandatory = $false)]
        [string]$ExportPath = "C:\Temp\AD_Groups.csv"
    )

    Log-Message "Export of groups from the OU has begun. : $OUPath" "INFO"

    $allResults = @()
    $groups = Get-ADGroup -Filter * -SearchBase $OUPath -SearchScope Subtree -Properties SamAccountName, Name, DistinguishedName

    foreach ($group in $groups) {
        try {
            # Retrieves all user members, including nested ones.
            $members = Get-ADGroupMember -Identity $group.DistinguishedName -Recursive -ErrorAction Stop |
                       Where-Object { $_.objectClass -eq 'user' }

            foreach ($m in $members) {
                $user = Get-ADUser -Identity $m.DistinguishedName -Properties UserPrincipalName
                $allResults += [PSCustomObject]@{
                    GroupName = $group.Name
                    GroupSAM  = $group.SamAccountName
                    MemberSAM = $user.SamAccountName
                    MemberUPN = $user.UserPrincipalName
                }
            }

            Log-Message " Treated group: $($group.Name)" "SUCCESS"
        }
        catch {
            Log-Message "Error processing the group $($group.Name) : $($_.Exception.Message)" "ERROR"
        }
    }

    if ($allResults.Count -gt 0) {
        $dir = Split-Path $ExportPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $allResults | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Log-Message " Export completed successfully : $ExportPath" "SUCCESS"
    }
    else {
        Log-Message " No members found in the OU groups $OUPath" "WARNING"
    }
}


#endregion

#region - Export function for AD (direct) groups of users in an OU
function Export-UserGroupMemberships {
    param (
        [string]$OUPath , # Exemple : "OU=Finance,OU=Utilisateurs,DC=contoso,DC=contoso,DC=local"
        [string]$ExportPath = "C:\Temp\User_Group_Memberships.csv"
    )

    Log-Message "Export of user OU group memberships has begun : $OUPath" "INFO"

    try {
        $users = Get-ADUser -SearchBase $OUPath -Filter * -Properties SamAccountName
        $exportData = @()

        foreach ($user in $users) {
            $groups = Get-ADUser -Identity $user.SamAccountName | Get-ADPrincipalGroupMembership
            foreach ($group in $groups) {
                $exportData += [PSCustomObject]@{
                    UserSAM   = $user.SamAccountName
                    GroupSAM  = $group.SamAccountName
                    GroupName = $group.Name
                }
            }
        }

        if ($exportData.Count -gt 0) {
            $exportData | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8 -Delimiter ","
            Log-Message "Membership export complete. File : $ExportPath" "SUCCESS"
        } else {
            Log-Message "No group memberships found for users." "WARNING"
        }
    } catch {
        Log-Message "Error during group membership export : $_" "ERROR"
    }
}

#endregion

#region - User import function with OU specification
function Import-ADUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OUPath, # Exemple : "OU=Finance,OU=Utilisateurs,DC=contoso,DC=contoso,DC=local"

        [Parameter(Mandatory = $true)]
        [string]$exportUsersFile = $global:exportUsersFile
    )

    # ============================================
    # Étape 1 : define the Microsoft 365 domain
    # ============================================
    Write-Host ""
    Write-Host " Example: if your Microsoft 365 domain is 'contoso.onmicrosoft.com'," -ForegroundColor Yellow
    Write-Host "   Simply enter 'contoso' below." -ForegroundColor Yellow
    Write-Host ""

    $Company = Read-Host "Please enter your Microsoft 365 domain name (without .onmicrosoft.com)"
    $userUPNSuffix = "@$Company.onmicrosoft.com"

    Log-Message "User import has begun into the OU : $OUPath (suffixe UPN = $userUPNSuffix)" "INFO"

    if (!(Test-Path $exportUsersFile)) {
        Log-Message "File not found : $exportUsersFile" "ERROR"
        return
    }

    $users = Import-Csv -Path $exportUsersFile

    foreach ($user in $users) {
        if ([string]::IsNullOrWhiteSpace($user.SamAccountName)) {
            Log-Message "Line ignored : SamAccountName empty in the CSV file." "WARNING"
            continue
        }

        # Building the new UPN with a Microsoft 365 domain
        $userUPN = "$($user.SamAccountName)$userUPNSuffix"

        # Checks if the user already exists
        $existingUser = Get-ADUser -Filter { UserPrincipalName -eq $userUPN } -ErrorAction SilentlyContinue

        if (-not $existingUser) {
            try {
                $otherAttributes = @{}
                if (-not [string]::IsNullOrWhiteSpace($user.FacsimileTelephoneNumber)) {
                    $otherAttributes["facsimileTelephoneNumber"] = $user.FacsimileTelephoneNumber
                }

                $params = @{
                    UserPrincipalName = $userUPN
                    SamAccountName    = $user.SamAccountName
                    GivenName         = $user.GivenName
                    Surname           = $user.Surname
                    Name              = $user.DisplayName
                    DisplayName       = $user.DisplayName
                    Description       = $user.Description
                    OfficePhone       = $user.TelephoneNumber
                    EmailAddress      = $user.EmailAddress
                    StreetAddress     = $user.StreetAddress
                    PostalCode        = $user.PostalCode
                    City              = $user.City
                    Country           = $user.Country
                    Title             = $user.Title
                    Department        = $user.Department
                    Company           = $user.Company
                    Enabled           = $true
                    AccountPassword   = (ConvertTo-SecureString -AsPlainText "ComplexPassword1234!" -Force)
                    PassThru          = $true
                    Path              = $OUPath
                }

                if ($otherAttributes.Count -gt 0) {
                    $params["OtherAttributes"] = $otherAttributes
                }

                $targetUser = New-ADUser @params
                Log-Message " User $userUPN created in the OU $OUPath." "SUCCESS"
            }
            catch {
                Log-Message " Error creating user $userUPN : $_" "ERROR"
                continue
            }
        }
        else {
            Log-Message " User $userUPN already exists — update attributes..." "INFO"
            $targetUser = $existingUser
        }

        # --- Proxy Address Update ---
        if ($user.ProxyAddresses) {
            try {
                $proxyList = $user.ProxyAddresses -split ",\s*"
                Set-ADUser -Identity $targetUser.DistinguishedName -Add @{ ProxyAddresses = $proxyList }
                Log-Message " ProxyAddresses added for $userUPN." "SUCCESS"
            }
            catch {
                Log-Message "Error adding ProxyAddresses for $userUPN : $_" "ERROR"
            }
        }

        # --- Added the adminDescription attribute ---
        try {
            Set-ADUser -Identity $targetUser -Replace @{ adminDescription = "User_NoSync" }
            Log-Message " adminDescription updated for $userUPN." "SUCCESS"
        }
        catch {
            Log-Message " Error updating adminDescription for $userUPN : $_" "ERROR"
        }
    }

    Log-Message " User import completed successfully." "SUCCESS"
}



#endregion

#region - Security group import function with OU selection
function Import-ADGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OUPath,  # Ex : "OU=Mdg,OU=Corporate,DC=contoso,DC=local"

        [Parameter(Mandatory = $true)]
        [string]$exportGroupsFile = "C:\Temp\AD_Groups.csv"
    )

    Log-Message " Importing groups has begun since : $exportGroupsFile" "INFO"

    # Checks for the existence of the CSV file
    if (!(Test-Path $exportGroupsFile)) {
        Log-Message " File not found : $exportGroupsFile" "ERROR"
        return
    }

    # Import CSV in simple format (GroupName, GroupSAM, MemberSAM, MemberUPN)
    $groupsRaw = Import-Csv -Path $exportGroupsFile -Delimiter ','

    # Liste unique de tous les groupes à (re)créer
    $allGroupSAMs = $groupsRaw.GroupSAM | Sort-Object -Unique

    foreach ($sam in $allGroupSAMs) {
        if ([string]::IsNullOrWhiteSpace($sam)) { continue }

        # Check if the group already exists
        $existingGroup = Get-ADGroup -Filter { SamAccountName -eq $sam } -ErrorAction SilentlyContinue
        if (-not $existingGroup) {
            try {
                New-ADGroup -Name $sam `
                            -SamAccountName $sam `
                            -GroupScope Global `
                            -GroupCategory Security `
                            -Path $OUPath `
                            -ErrorAction Stop
                Log-Message "Group created: $sam (OU = $OUPath)" "SUCCESS"
            } catch {
                Log-Message " Error creating group $sam : $($_.Exception.Message)" "ERROR"
            }
        }
        else {
            Log-Message "Already existing group : $sam — no change" "INFO"
        }
    }

    # Adding user members to groups
    foreach ($line in $groupsRaw) {
        $groupSam  = $line.GroupSAM
        $memberSam = $line.MemberSAM

        if ([string]::IsNullOrWhiteSpace($groupSam) -or [string]::IsNullOrWhiteSpace($memberSam)) {
            continue
        }

        # Searching for a member (user or group)
        $memberObject = Get-ADUser -Filter { SamAccountName -eq $memberSam } -ErrorAction SilentlyContinue
        if (-not $memberObject) {
            $memberObject = Get-ADGroup -Filter { SamAccountName -eq $memberSam } -ErrorAction SilentlyContinue
        }

        if (-not $memberObject) {
            Log-Message "Member not found : $memberSam (ignoré)" "WARNING"
            continue
        }

        try {
            Add-ADGroupMember -Identity $groupSam -Members $memberObject -ErrorAction Stop
            Log-Message "Member $memberSam added to the group $groupSam" "SUCCESS"
        } catch {
            # Ignore duplicate entries like "is already a member of" to avoid noise in the logs.
            if ($_.Exception.Message -match "already a member") {
                Log-Message "$memberSam is already a member of the group $groupSam" "INFO"
            } else {
                Log-Message "Error adding $memberSam to $groupSam : $($_.Exception.Message)" "ERROR"
            }
        }
    }

    Log-Message "Group import complete." "SUCCESS"
}


#endregion

#region - User group import function
function Import-UserGroupMemberships {
    param (
        [string]$ImportPath = "C:\Temp\User_Group_Memberships.csv"
    )

    Log-Message "Importing user group memberships has begun...." "INFO"

    if (!(Test-Path $ImportPath)) {
        Log-Message "File $ImportPath not found." "ERROR"
        return
    }

    $entries = Import-Csv -Path $ImportPath -Delimiter ','

    foreach ($entry in $entries) {
        $userSam  = $entry.UserSAM
        $groupSam = $entry.GroupSAM

        $user = Get-ADUser -Filter { SamAccountName -eq $userSam } -ErrorAction SilentlyContinue
        $group = Get-ADGroup -Filter { SamAccountName -eq $groupSam } -ErrorAction SilentlyContinue

        if (-not $user) {
            Log-Message "User $userSam not found in AD." "WARNING"
            continue
        }

        if (-not $group) {
            Log-Message "Group $groupSam not found in AD." "WARNING"
            continue
        }

        try {
            Add-ADGroupMember -Identity $groupSam -Members $userSam -ErrorAction Stop
            Log-Message "User $userSam added to the group $groupSam." "SUCCESS"
        } catch {
            Log-Message "Error adding $userSam to the group $groupSam : $_" "ERROR"
        }
    }

    Log-Message "Import of user memberships complete." "SUCCESS"
}

#endregion

#region - Proxy Address Import Function
function Update-ADProxyAddressesFromCsv {
    [CmdletBinding(SupportsShouldProcess)]
   <# param (
        [Parameter(Mandatory = $true)]
        [string]$exportUsersFile
    )#>

    # Import CSV data
    $users = Import-Csv -Path $global:exportUsersFile

    foreach ($user in $users) {
        $username = $user.SamAccountName
        Write-Host "`n--- Treatment of $username ---"

        if (-not $username) {
            Write-Warning "SamAccountName missing, ignored line."
            continue
        }

        $proxyRaw = $user.ProxyAddresses
        if (-not $proxyRaw) {
            Write-Host "No proxy address specified for $username" -ForegroundColor Cyan
            continue
        }

        # Separate the addresses and clean
        $proxyList = $proxyRaw -split ",\s*" | ForEach-Object { $_.Trim() }

        try {
            $adUser = Get-ADUser -Identity $username -Properties ProxyAddresses
        } catch {
            Write-Warning "User $username not found in AD."
            continue
        }

        $currentProxies = @()
        if ($adUser.ProxyAddresses) {
            $currentProxies = $adUser.ProxyAddresses
        }

        # Determine the addresses to add
        $toAdd = $proxyList | Where-Object { $currentProxies -notcontains $_ }

        if ($toAdd.Count -gt 0) {
            $toAddClean = @($toAdd | ForEach-Object { [string]$_ })
            Write-Host "Ajout de : $($toAddClean -join ', ')" -ForegroundColor Green

            if ($PSCmdlet.ShouldProcess($username, "Add proxy addresses")) {
                try {
                    Set-ADUser -Identity $adUser.DistinguishedName -Add @{ ProxyAddresses = $toAddClean }
                } catch {
                    Write-Error "Error adding for $username : $_"
                }
            }
        } else {
            Write-Host "No update required for $username" -ForegroundColor White
        }
    }
}

#endregion

#region - Import Manager Function
function Set-ADUserManagerFromCsv {
    [CmdletBinding()]
    param(
        [string]$exportUsersFile = $global:exportUsersFile
    )

    if (!(Test-Path $exportUsersFile)) {
        Write-Error "File not found : $exportUsersFile"
        return
    }

    $users = Import-Csv -Path $exportUsersFile

    foreach ($user in $users) {
        $sam = $user.SamAccountName
        $managerDN = $user.Manager

        if (-not $sam -or -not $managerDN) {
            Write-Warning "Missing data for $sam, line ignored."
            continue
        }

        try {
            # Extract the CN from the manager's DN
            $managerCN = ($managerDN -split ',')[0] -replace '^CN='

            # Search for the manager's AD object by CN
            $manager = Get-ADUser -Filter { Name -eq $managerCN } -Properties DistinguishedName -ErrorAction Stop

            # Assign the manager to the user
            Set-ADUser -Identity $sam -Manager $manager.DistinguishedName

            Write-Host " Manager '$managerCN' assigned to '$sam'" -ForegroundColor Green
        } catch {
            Write-Error "Error for $sam : $_"
        }
    }
}

#endregion

#region - Fonction d'update de l'attribut Salesforce ID
function Update-ADSalesForceProfileIDFromCsv {
    [CmdletBinding()]
    param(
        [string]$exportUsersFile = $global:exportUsersFile
    )

    if (!(Test-Path $exportUsersFile)) {
        Write-Error "File not found: $exportUsersFile"
        return
    }

    $users = Import-Csv -Path $exportUsersFile

    foreach ($user in $users) {
        $sam = $user.SamAccountName
        $sfID = $user.SalesForceProfileID

        if (-not $sam -or -not $sfID) {
            Write-Warning "SamAccountName or missing SalesforceProfileID for a line, ignored."
            continue
        }

        try {
            Set-ADUser -Identity $sam -Replace @{SalesForceProfileID = $sfID}
            Write-Host " SalesforceProfileID attribute updated for $sam : $sfID" -ForegroundColor Green
        } catch {
            Write-Error " Error during update for $sam : $_"
        }
    }
}

#endregion

#region - UPN modification function
function Update-UPNSuffixInOU {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OUPath , # Exemple : "OU=Finance,OU=Utilisateurs,DC=contoso,DC=contoso,DC=local"

        [string]$NewUPNSuffix 
    )

    Log-Message "UPN updates have begun in the OU : $OUPath" "INFO"

    try {
        $users = Get-ADUser -SearchBase $OUPath -Filter * -Properties UserPrincipalName

        foreach ($user in $users) {
            if ($user.UserPrincipalName -match "(.+)@(.+)") {
                $newUPN = "$($matches[1])@$NewUPNSuffix"

                if ($user.UserPrincipalName -ne $newUPN) {
                    try {
                        Set-ADUser -Identity $user.DistinguishedName -UserPrincipalName $newUPN
                        Log-Message "UPN of $($user.SamAccountName) updated to $newUPN" "SUCCESS"
                    } catch {
                        Log-Message "Error updating UPN for $($user.SamAccountName) : $_" "ERROR"
                    }
                } else {
                    Log-Message "UPN of $($user.SamAccountName) already compliant, no modification required." "INFO"
                }
            } else {
                Log-Message "Invalid or missing UPN for $($user.SamAccountName), ignored." "WARNING"
            }
        }

        Log-Message "UPN update complete for the OU : $OUPath" "SUCCESS"
    } catch {
        Log-Message "Unexpected error while retrieving users from the OU : $_" "ERROR"
    }
}

#endregion

#region - Function to remove the immutable ID
function Clear-O365ImmutableIdInOU {
    param (
        [Parameter(Mandatory = $true)]
        [string]$OUPath  ,  # Exemple : "OU=Finance,OU=Utilisateurs,DC=contoso,DC=local"

        [string]$ExportPath = "C:\Temp\ImmutableId_Report.csv"
    )

    Log-Message "Beginning of the removal of ImmutableIds in the OU : $OUPath" "INFO"

    Connect-MgGraph -Scopes "User.Read.All", "Group.ReadWrite.All"

    $report = @()

    try {
        $users = Get-ADUser -SearchBase $OUPath -Filter * -Properties UserPrincipalName

        foreach ($user in $users) {
            $upn = $user.UserPrincipalName

            if (-not $upn) {
                Log-Message "User $($user.SamAccountName) without UPN, ignored." "WARNING"
                continue
            }

            try {
                $cloudUser = Get-MgUser -UserId $upn -Property onPremisesImmutableId, displayName

                if ($cloudUser.onPremisesImmutableId) {
                    Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$upn" `
                        -Body @{onPremisesImmutableId = $null}

                    Log-Message "ImmutableId removed for $upn" "SUCCESS"

                    $report += [PSCustomObject]@{
                        UPN                 = $upn
                        DisplayName         = $cloudUser.displayName
                        ImmutableId_Deleted = "Yes"
                        Message             = "Successfully deleted"
                    }
                } else {
                    Log-Message "No ImmutableId is present for $upn, nothing to be done." "INFO"

                    $report += [PSCustomObject]@{
                        UPN                 = $upn
                        DisplayName         = $cloudUser.displayName
                        ImmutableId_Deleted = "No"
                        Message             = "null"
                    }
                }
            } catch {
                Log-Message "Error for $upn : $_" "ERROR"

                $report += [PSCustomObject]@{
                    UPN                 = $upn
                    DisplayName         = $user.Name
                    ImmutableId_Deleted = "No"
                    Message             = "Error : $_"
                }
            }
        }

        # Exporting the report
        if ($report.Count -gt 0) {
            $report | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
            Log-Message "Exported execution report to $ExportPath" "INFO"
        }

        Log-Message "Treatment completed for the OU: $OUPath" "SUCCESS"
    } catch {
        Log-Message "Global error when accessing the OU or Graph : $_" "ERROR"
    }
}

#endregion

#region - Function Adding the usernosync attribute
function Set-AdminDescriptionToNoSync {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OUPath ,  

        [string]$ExportPath = "C:\Temp\AdminDescription_Update_Report.csv"
    )

    Log-Message "Beginning of the update of the adminDescription attribute in the OU : $OUPath" "INFO"

    $report = @()

    try {
        $users = Get-ADUser -SearchBase $OUPath -Filter * -Properties adminDescription

        foreach ($user in $users) {
            $currentValue = $user.adminDescription

            if ($currentValue -ne "User_NoSync") {
                try {
                    Set-ADUser -Identity $user.DistinguishedName -Replace @{ adminDescription = "User_NoSync" }
                    Log-Message "adminDescription modifié pour $($user.SamAccountName)" "SUCCESS"

                    $report += [PSCustomObject]@{
                        SamAccountName     = $user.SamAccountName
                        DisplayName        = $user.Name
                        PreviousValue      = $currentValue
                        NewValue           = "User_NoSync"
                        Status             = "Modified"
                    }
                } catch {
                    Log-Message "Error modifying $($user.SamAccountName) : $_" "ERROR"

                    $report += [PSCustomObject]@{
                        SamAccountName     = $user.SamAccountName
                        DisplayName        = $user.Name
                        PreviousValue      = $currentValue
                        NewValue           = "User_NoSync"
                        Status             = "Error"
                    }
                }
            } else {
                Log-Message "$($user.SamAccountName) already has the correct value, no changes." "INFO"

                $report += [PSCustomObject]@{
                    SamAccountName     = $user.SamAccountName
                    DisplayName        = $user.Name
                    PreviousValue      = $currentValue
                    NewValue           = "User_NoSync"
                    Status             = "Already compliant"
                }
            }
        }

        if ($report.Count -gt 0) {
            $report | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
            Log-Message "Rexported contribution : $ExportPath" "INFO"
        }

        Log-Message "Update of the adminDescription attribute in the OU is complete. : $OUPath" "SUCCESS"
    } catch {
        Log-Message "Global error : $_" "ERROR"
    }
}

#endregion

#region - Function to remove the UserNosync value in Admindescription
function Clear-AdminDescriptionInOU {
    param (
        [Parameter(Mandatory=$true)]
        [string]$OUPath
    )

    Log-Message "Beginning of the cleanup of the adminDescription attribute in the OU : $OUPath" "INFO"

    try {
        $users = Get-ADUser -SearchBase $OUPath -Filter * -Properties adminDescription
        foreach ($user in $users) {
            if ($user.adminDescription) {
                try {
                    Set-ADUser -Identity $user.SamAccountName -Clear "adminDescription"
                    Log-Message "adminDescription deleted for : $($user.SamAccountName)" "SUCCESS"
                } catch {
                    Log-Message "Error deleting $($user.SamAccountName) : $_" "ERROR"
                }
            } else {
                Log-Message "No values ​​to clear for: $($user.SamAccountName)" "INFO"
            }
        }
    } catch {
        Log-Message "Error retrieving users : $_" "ERROR"
    }

    Log-Message "Cleaning completed." "SUCCESS"
}

#endregion

#region - Function to disable AD accounts in an OU
function Disable-ADAccountsFromOU {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OUPath
    )

    Log-Message "Account deactivation begins in the OU: $OUPath" "INFO"

    try {
        # Retrieves all active users from the OU (including sub-OUs)
        $users = Get-ADUser -Filter { Enabled -eq $true } -SearchBase $OUPath -SearchScope Subtree -ErrorAction Stop
    }
    catch {
        Log-Message "Error retrieving users from the OU $OUPath : $_" "ERROR"
        return
    }

    if (-not $users) {
        Log-Message "No active accounts found in the OU $OUPath." "WARNING"
        return
    }

    foreach ($user in $users) {
        try {
            Disable-ADAccount -Identity $user.SamAccountName -ErrorAction Stop
            Log-Message "Account disabled : $($user.SamAccountName)" "SUCCESS"
        }
        catch {
            Log-Message "Error deactivating account $($user.SamAccountName) : $_" "ERROR"
        }
    }

    Log-Message "End of account deactivation in the OU : $OUPath" "SUCCESS"
}
#endregion

#region - Restore and reassign UPN function from an OU
function Enable-AccountsFromOU {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OUPath,

        [Parameter(Mandatory = $false)]
        [string]$Domain ,

        [Parameter(Mandatory = $false)]
        [string]$NEWDOMAIN
    )

    Log-Message "Start - Restoration/UPN from OR : $OUPath (old domain: $Domain | new domain: $NEWDOMAIN)" "INFO"

    try {
        # Retrieve the list of accounts (the entire OU, including subOUs)
        $adUsers = Get-ADUser -Filter * -SearchBase $OUPath -SearchScope Subtree -Properties SamAccountName -ErrorAction Stop
    }
    catch {
        Log-Message "AD retrieval error in the OU $OUPath : $($_.Exception.Message)" "ERROR"
        return
    }

    if (-not $adUsers) {
        Log-Message "No users found in the OU $OUPath." "WARNING"
        return
    }

    # Connexion MSGraph
    try {
        Connect-MgGraph -Scopes "User.Read.All","User.ReadWrite.All" | Out-Null
    }
    catch {
        Log-Message "Connection to Microsoft Graph failed : $($_.Exception.Message)" "ERROR"
        return
    }

    # Load all deleted users (trash) and index by UPN (lower)
    try {
        $deletedUsers = Get-MgDirectoryDeletedItemAsUser -All
    }
    catch {
        Log-Message "Error reading recycle bin (deleted users) : $($_.Exception.Message)" "ERROR"
        return
    }

    $deletedByUpn = @{}
    foreach ($du in $deletedUsers) {
        if ($du.UserPrincipalName) {
            $deletedByUpn[$du.UserPrincipalName.ToLower()] = $du
        }
    }

    # For each AD user in the OU, try restoring and updating the UPN.
    foreach ($adUser in $adUsers) {
        if ([string]::IsNullOrWhiteSpace($adUser.SamAccountName)) {
            Log-Message "Ignored line (empty SamAccountName) for AD object : $($adUser.DistinguishedName)" "WARNING"
            continue
        }

        $OldUPN = "$($adUser.SamAccountName)@$Domain"
        $NewUPN = "$($adUser.SamAccountName)@$NEWDOMAIN"
        $oldKey = $OldUPN.ToLower()

        try {
            $DeletedUser = $null
            if ($deletedByUpn.ContainsKey($oldKey)) {
                $DeletedUser = $deletedByUpn[$oldKey]
            }
            else {
                # fallback: broad search if needed (rare) – avoids false negatives if the exact UPN was modified before deletion
                $DeletedUser = $deletedUsers | Where-Object { $_.UserPrincipalName -like "*$OldUPN*" } | Select-Object -First 1
            }

            if ($DeletedUser) {
                # 4.a) Restore
                $Restored = Restore-MgDirectoryDeletedItem -DirectoryObjectId $DeletedUser.Id
                Log-Message "Restauré : $OldUPN" "SUCCESS"

                # 4.b) Wait for propagation and update the UPN
                Start-Sleep -Seconds 2

                Update-MgUser -UserId $DeletedUser.Id -UserPrincipalName $NewUPN
                Log-Message " UPN modifié : $OldUPN -> $NewUPN" "SUCCESS"
            }
            else {
                Log-Message " Deleted user not found in the recycle bin : $OldUPN" "WARNING"
            }
        }
        catch {
            Log-Message "Treatment failure $OldUPN : $($_.Exception.Message)" "ERROR"
        }
    }

    Log-Message "End - Restore/UPN from OR : $OUPath" "SUCCESS"
}
#endregion



# Menu interactif
do {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           SCRIPT DE MIGRATION ACTIVE DIRECTORY v2.0                   ║" -ForegroundColor Yellow
    Write-Host "╠═══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║                                                                       ║" -ForegroundColor Cyan
    Write-Host "║  EXPORT (AD Source)                                                   ║" -ForegroundColor Yellow
    Write-Host "║  1.  Export users                                                     ║" -ForegroundColor White
    Write-Host "║  2.  Export security groups                                           ║" -ForegroundColor White
    Write-Host "║  3.  Export the 'members of' users from an OU                         ║" -ForegroundColor White
    Write-Host "║                                                                       ║" -ForegroundColor Cyan
    Write-Host "║  IMPORT (AD Target)                                                   ║" -ForegroundColor Yellow
    Write-Host "║  4.  Import users                                                     ║" -ForegroundColor White
    Write-Host "║  5.  Import security groups                                           ║" -ForegroundColor White
    Write-Host "║  6.  Import the 'members of' users from an OU                         ║" -ForegroundColor White
    Write-Host "║                                                                       ║" -ForegroundColor Cyan
    Write-Host "║  ATTRIBUTE MANAGEMENT (AD Target)                                     ║" -ForegroundColor Yellow
    Write-Host "║  7.  Update ProxyAddresses                                            ║" -ForegroundColor White
    Write-Host "║  8.  Update the Managers                                              ║" -ForegroundColor White
    Write-Host "║  9.  Update Salesforce IDs                                            ║" -ForegroundColor White
    Write-Host "║  10. Edit the UPN Suffix                                              ║" -ForegroundColor White
    Write-Host "║  11. Clear the 'User_NoSync' attribute                                ║" -ForegroundColor White
    Write-Host "║  12. Add the 'User_NoSync' attribute (AD Source)                      ║" -ForegroundColor White
    Write-Host "║                                                                       ║" -ForegroundColor Cyan
    Write-Host "║  MICROSOFT 365                                                        ║" -ForegroundColor Yellow
    Write-Host "║  13. Remove the Immutable ID (Graph) (Bounce)                         ║" -ForegroundColor White
    Write-Host "║                                                                       ║" -ForegroundColor Cyan
    Write-Host "║  AUTRES                                                               ║" -ForegroundColor Yellow
    Write-Host "║  14. Disable the AD account (AD Source)                               ║" -ForegroundColor White
    Write-Host "║  15. O365 account reactivation and UPN modification (Graph) (Rebound) ║" -ForegroundColor White
    Write-Host "║                                                                       ║" -ForegroundColor Cyan
    Write-Host "║                                                                       ║" -ForegroundColor Cyan
    Write-Host "║ 16. Exit                                                              ║" -ForegroundColor White
    Write-Host "║                                                                       ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    $choice = Read-Host "Choose an option"

    switch ($choice) {
        "1" { 
            $Oupath = Read-Host "Enter the value Oupath"  
            Export-ADUsers -OUPath $OUPath }

        "2" {
            $Oupath = Read-Host "Enter the value Oupath"
            Export-ADGroups -OUPath $OUPath }

        "3" { 
            $Oupath = Read-Host "Enter the value Oupath"
            Export-UserGroupMemberships -OUPath $OUPath }

        "4" { 
            $Oupath = Read-Host "Enter the value Oupath"
            Import-ADUsers -OUPath $OUPath }

        "5" { 
            $Oupath = Read-Host "Enter the value Oupath"
            Import-ADGroups -OUPath $OUPath }

        "6" { Import-UserGroupMemberships }
        "7" { Update-ADProxyAddressesFromCsv }
        "8" { Set-ADUserManagerFromCsv }
        "9" { Update-ADSalesForceProfileIDFromCsv }

        "10" { 
            $Oupath = Read-Host "Enter the value Oupath"
            $NewUPNSuffix  = Read-Host "Enter the value of the new UPN suffix, for example : 'contoso.com' ou contoso.onmicrosoft.com "
            Update-UPNSuffixInOU -OUPath $OUPath -NewUPNSuffix $NewUPNSuffix }

        "11" { 
            $Oupath = Read-Host "Enter the value Oupath"
            Clear-AdminDescriptionInOU -OUPath $OUPath }
        "12" { 
            $Oupath = Read-Host "Enter the value Oupath"
            Set-AdminDescriptionToNoSync -OUPath $OUPath }

        "13" { 
            $Oupath = Read-Host "Enter the value Oupath"
            Clear-O365ImmutableIdInOU -OUPath $OUPath }

        "14" {
            $Oupath = Read-Host "Enter the value Oupath"
            $Domain = Read-Host "Enter the existing domain example: contoso.onmicrosoft.com" 
            $NEWDOMAIN = Read-Host "Enter the new example domain: contoso.com" 
            Disable-ADAccountsFromOU -OUPath $OUPath -Domain $Domain -NEWDOMAIN $NEWDOMAIN}

        "15" { 
            $Oupath = Read-Host "Enter the value Oupath"
            Enable-AccountsFromOU }

        "16" { Write-Host "Closing the script..." ; break }
        default { Write-Host "Invalid choice, please try again.." }
    }
    Pause
} while ($choice -ne "16")
