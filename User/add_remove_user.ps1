<# Create or deprovision a TinyCo user

    Graph permissions required aka for ITOps only
        User.ReadWrite.All
        Group.ReadWrite.All
        RoleManagement.ReadWrite.Directory

    Create switch requires a firstname, lastname and team/department parameters
    :: Example: > .\add_remove_user.ps1 -create -firstname "Ella" -lastname "Eider" -team "Security"

        1 Creates a user account with these properties
            .displayName       = "$firstname $lastname"
            .givenName         = "$firstname"
            .lastname          = "$lastname"
            .userPrincipalName = "$firstname.$lastname@tinyco.xyz"
            .mail              = "$firstname.$lastname@tinyco.cyz"
            .department        = $team

        2 Adds user to any PIM-DEPT group matching PIM-$team format
        :: Example: Adds to PIM-RBAC-security_reader group for Security team members (hardcoded)

    Deprovision switch accepts an email address of string x.x@tinyco.xyz
    :: Example: > .\add_remove_user.ps1 -deprov -email ella.eider@tinyco.xyz

        1 Set user account to disabled
        2 Remove from any PIM-RBAC or PIM-DEPT the user is a member of
        3 Revoke any active auth tokens

#>

[CmdletBinding()]
param(# Input parameters for deprovision and create. These then map to a parameter set controlling what's used in both scenarios
    
    [Parameter(Mandatory=$true, ParameterSetName='create')]
    [switch]$create, # If -Create, make a pset called create

    [Parameter(Mandatory=$true, ParameterSetName='deprov')]
    [switch]$deprov,

    [Parameter(Mandatory=$true, ParameterSetName='create')] # Mandatory inputs for -action create
    [string]$firstname,

    [Parameter(Mandatory=$true, ParameterSetName='create')]
    [string]$lastname,

    [Parameter(Mandatory=$true, ParameterSetName='create')]
    [string]$team,

    [Parameter(Mandatory=$true, ParameterSetName='deprov')] # Mandatory input for -action deprov
    [ValidatePattern('^[a-zA-Z0-9._%+-]+@tinyco\.xyz$')]
    [string]$email

)

$action = $PSCmdlet.ParameterSetName # Get the active parameter set, ie create or deprov

switch($action) {# Note there is no error checking (don't create if duplicate) or handling (try/catch/break) here given the project deadline

    "create"{

        # Set the basics
        $displayName = "$firstname $lastname"
        $upn       = ("$firstname.$lastname@tinyco.xyz").ToLower()
        Write-Output "=== $displayname ===`nAttempting to create $displayname`n`tMail: $upn`n`tDepartment: $team"

        $pass = @{ # Generate totally secure password
            Password = "$firstname!!2025"
            forceChangePasswordNextSignIn = $true
        }

        # Create the user and store the resulting Id for later
        $newUserId = New-MgUser -DisplayName $displayName -GivenName $firstname -Surname $lastname -Mail $upn -UserPrincipalName $upn -Department $team -AccountEnabled -PasswordProfile $pass -MailNickname "$firstname.$lastname"
        Start-Sleep -Seconds 2 # ... Yes,I know, but this is for demo purposes

        # Check if a PIM-DEPT-$team group exists. Replace spaces with underscores, lowercase suffix
        Write-Output "`nChecking for PIM-DEPT-$($team.ToLower() -Replace ' ', '_')"
        $pimDeptGroup = Get-MgGroup -Filter ("displayName eq 'PIM-DEPT-$($team.ToLower() -Replace ' ', '_')'")
        
        if($pimDeptGroupId){ # If it finds a match, add the user
            Write-Output "`tFound $($pimDeptGroup.DisplayName)`n`t + Adding $upn"
            New-MgGroupMember -GroupID $pimDeptGroup.Id -DirectoryObjectId $newUserId.Id
        }

        if($team -eq "Security"){ # If $team is Security, add to PIM-RBAC-security_reader group
            Write-Output "`tNew member of the Security team detected`n`t + Adding $upn to PIM-RBAC-security_reader"
            $pimRBACGroup = Get-MgGroup -Filter ("displayName eq 'PIM-RBAC-security_reader'")
            [string]$existUserId = $NewUserId.id # Force a user id string as New-MgGroupMember will not accept .ID here, even though it accepts it a few lines earlier for the same thing
            New-MgGroupMember -GroupId $pimRBACGroup.Id -DirectoryObjectId $existUserId
        }

        if($team -eq "ITOps"){ # If $team is ITOps, add to PIM-RBAC-g_a group
            Write-Output "`tNew member of the ITOps team detected`n`t + Adding $upn to PIM-RBAC-global_administrator"
            $pimRBACGroup = Get-MgGroup -Filter ("displayName eq 'PIM-RBAC-global_administrator'")
            [string]$existUserId = $NewUserId.id # Force a user id string as New-MgGroupMember will not accept .ID here, even though it accepts it a few lines earlier for the same thing
            New-MgGroupMember -GroupId $pimRBACGroup.Id -DirectoryObjectId $existUserId
        }
    }

    "deprov"{
        
        # Set the basics
        Write-Output "Attempting to deprovision $email. Checking for user..."
        $goodbyeUserDetails = Get-MgUser -Filter ("userPrincipalName eq '$mail'")
        $goodbyeUserId = $goodbyeUserDetails.Id 
        
        if($goodbyeUserId){ # Set to disabled, remove auth tokens from Entra

            Write-Output "Found $($goodbyeUserDetails.mail) [$($goodbyeUserId)] - deprovisioning..."
            Revoke-MgUserSignInSession -UserID $goodbyeUserId
            Update-MgUser -UserId $goodbyeUserDetails.Id -AccountEnabled:$false

            # For housekeeping in lieu of Azure policies...
            $userGroups = Get-MgUserMemberOf -UserID $goodbyeUserId | % {($_.AdditionalProperties).displayName} | ForEach-Object { # Find the users group memberships and grab their displaynames
                
                if($_ -Like "PIM-*"){ # If the displayName begins with PIM, lookup is Id and remove the user from it"

                    $pimDeptGroupId = (Get-MgGroup -Filter ("displayName eq '$_'")).Id
                    Write-Host "`n`tFound membership to $_ ($pimDeptGroupId).`n`tRemoving - $mail..."
                    Remove-MgGroupMemberByRef -GroupId $pimDeptGroupId -DirectoryObjectId $goodbyeUserId

                }
            } 
        }
    }
}