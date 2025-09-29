<#
    This script is used to create and populate groups at the fictional TinyCo organization

    1. Required PowerShell modules
        Graph API, install with 'Install-Module -Name Microsoft.Graph'

    2. Required permissions for Graph API
        Group.ReadWrite.All, User.ReadWrite.All, RoleManagement.ReadWrite.Directory (add to role assigned groups)
        You'll need to be in the itops team to run this

    3. Required inputs
        The script references a CSV file named 'new_groups'. This file should be stored in the directory you're working from.
        Review the 'How to set up new groups' guide for more details
#>

# Set logic for mode 'apply' or 'plan'
param(
    [Parameter(Mandatory=$true)]
    [string]$action
)
if ($action -eq 'apply'){$mode = "apply"} else {$mode = "plan"}

<# Keeping the graph connection outside of this for simplicity of the admin guide
    Connect-MgGraph -scopes "Group.ReadWrite.All","User.Read","RoleManagement.ReadWrite.Directory"
#>

$tinyCoGroups = Import-Csv .\new_groups.csv

function setGroupDetails {
    param (
        [pscustomobject]$Group
    )

    # Enforce some kind of naming convention
    $groupName = switch ($Group.type) {
        "dept" { "DEPT-" + ($Group.name.ToLower() -Replace ' ', '_') }
        "app" { "APP-" + ($Group.name.ToLower() -Replace ' ', '_') }
        "pim-dept" { "PIM-DEPT-" + ($Group.name.ToLower() -Replace ' ', '_') }
        "pim-rbac" { "PIM-RBAC-" + ($Group.role.ToLower() -Replace ' ', '_') }
    }

    $groupDescription = switch ($Group.type) {
        "dept" { "Dynamic membership group for active members in the $($Group.name) team" }
        "app" { "Access group for the $($Group.name) application" }
        "pim-dept" { "PIM elibility for granular roles assigned to the $($Group.name) team" }
        "pim-rbac" { "PIM elibility for the $($Group.role) RBAC role" }

    }

    if($Group.type -eq "app") {
        # We need to create a string which entra accepts as valid string for the later membership rule using regex
        # | becomes "," :: [ becomes [" :: ] becomes "]. This was caused by my poor design choice early in the project :(
        $MembershipString = ($grp.members) -Replace '\|', '","' -Replace '\[(?=.*)','["' -Replace '\]$','"]'
    }

    $membershipRule = if ($Group.type -eq "app") {
        # Dyanamic App groups can have more than one department group, so we construct the rule using the above $membership string
        "(user.accountenabled -eq true) -and (user.department -in $membershipString)"
    } elseif ($Group.type -eq "dept") {
        "(user.accountenabled -eq true) -and (user.department -eq ""$($Group.name)"")"
    }

    [PSCustomObject]@{
        GroupName        = $groupName
        GroupDescription = $groupDescription
        MembershipRule   = $membershipRule
    }
}

foreach($grp in $tinyCoGroups){

    <# 
        Call the setGroupDetails function, passing in the current group object and saving the response as groupData
        - This will construct the group name and description for all groups
        - This will construct the membership rule string for any dynamic membership group such as department or application
    #>

    $groupData = setGroupDetails -group $grp
    Write-Host "`nRaw input: $grp`nProcessed: $groupData" -ForegroundColor Blue

    $groupName = $groupData.GroupName
    $groupDescription = $groupData.GroupDescription
    $membershipRule = $groupData.MembershipRule
    
    if($grp.type -eq "dept"){

        # Create the group
        Write-Host "$groupName will be a dynamic membership group for the $($grp.members) team`n`tDisplay Name: $groupName`n`tDescription: $groupDescription`n`tMembership Rule: $membershipRule`n`t...Creating"
        if($mode -eq "apply"){
            New-MgGroup -DisplayName $groupName -Description $groupDescription -SecurityEnabled -GroupTypes 'DynamicMembership' -MembershipRule $membershipRule -MembershipRuleProcessingState 'On' -MailEnabled:$False -MailNickName $groupName
        }
    }

    if($grp.type -eq "app"){

        Write-Host "$groupName will be a dynamic membership group for the $($grp.name) application`n`tDisplay Name: $groupName`n`tDescription: $groupDescription`n`tMembership Rule: $membershipRule`n`t...Creating"
        if($mode -eq "apply"){ # Only run on apply
            New-MgGroup -DisplayName $groupName -Description $groupDescription -SecurityEnabled -GroupTypes 'DynamicMembership' -MembershipRule $membershipRule -MembershipRuleProcessingState 'On' -MailEnabled:$False -MailNickName $groupName
        }
    }

    if($grp.type -eq "pim-dept"){

        # Create the group and store its Id for later
        Write-Host "$groupName will be an assigned security group for the $($grp.name) department`n`tDisplay Name: $groupName`n`tDescription: $groupDescription`n`t...Creating"
        if($mode -eq "apply"){# If check is used, don't create the group
            $newPimGroupId = (New-MgGroup -DisplayName $groupName -Description $groupDescription -SecurityEnabled -MailNickName $groupName -IsAssignableToRole -MailEnabled:$False).Id
        }

        <#
            -| Lookup members of the department group, filtering by displayname matching the tinco naming convention, store their Ids
            |- Iterate these in pipeline and construct an object of graph ids and save it as $pimGroupMembers
            => Use the object as the list of members in the Add-MgGroupMember command
        #>
        $deptGroupName = "DEPT-"+($($grp.members).ToLower() -Replace ' ', '_')
        $deptGroupId = (Get-MgGroup -Filter "DisplayName eq '$deptGroupName'").Id
        $deptGroupMemberIds = Get-MgGroupMember -GroupId $deptGroupId

        Write-Host "`t+= Adding $($deptGroupMemberIds.Count) from members of $deptGroupName" -ForegroundColor Green
        if($mode -eq "apply"){# If check is used, don't actually add anyone
            foreach($id in ($deptGroupMemberIds.Id)) {
                New-MgGroupMember -GroupId $newPimGroupId -DirectoryObjectId $id
            }   
        }

    }

    if($grp.type -eq "pim-rbac"){

        Write-Host "$groupName will be an assigned security group for the $($grp.role) role`n`tDisplay Name: $groupName`n`tDescription: $groupDescription`n`t...Creating"
        if($mode -eq "apply"){ #If check if used, don't actually create the group
            $newPimGroupId = (New-MgGroup -DisplayName $groupName -Description $groupDescription -SecurityEnabled -MailNickName $groupName -IsAssignableToRole -MailEnabled:$False).Id
        }

        # Get the list of group members, remove the '[]' from the input string then create objects from whatever is between/around instances of '|'
        foreach($team in ($grp.members).Trim('[]').Split('|')){

            $deptGroupName = "DEPT-"+($team.ToLower() -Replace ' ', '_')
            $deptGroupId = (Get-MgGroup -Filter "DisplayName eq '$deptGroupName'").Id
            $deptGroupMemberIds = Get-MgGroupMember -GroupId $deptGroupId

            Write-Host "`t+= Adding $($deptGroupMemberIds.Count) from members of $deptGroupName" -ForegroundColor Green
            if($mode -eq "apply"){ # If check is used, don't populate the group
                foreach($id in ($deptGroupMemberIds.Id)) {
                    New-MgGroupMember -GroupId $newPimGroupId -DirectoryObjectId $id
                }
            }
        } 
    }

}