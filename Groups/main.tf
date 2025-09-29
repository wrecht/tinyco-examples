locals {
  tiny_co_groups_csv = csvdecode(file("${path.module}/new_groups.csv"))# pwsh Import-Csv equivalent

  groups_data = {# set mapping, no real direct pwsh equivalent
    for group in local.tiny_co_groups_csv : "${group.type}-${group.name != "" ? group.name : group.role}" => group
  }

  processed_groups = {# pwsh function setGroupDetails equivalent
    for key, group in local.groups_data : key => {

      group_name = format("%s%s",# pwsh groupName equivalnet
        group.type == "dept" ? "DEPT-" :
        group.type == "app" ? "APP-" :
        group.type == "pim-dept" ? "PIM-DEPT-" :
        group.type == "pim-rbac" ? "PIM-RBAC-" :
        null,#...Great error handling v1
        lower(replace(group.name != "" ? group.name : group.role, " ", "_"))
      )

      group_description = (# pwsh $groupDescription equivalent
        group.type == "dept" ? "Dynamic membership group for active members in the ${group.name} team" :
        group.type == "app" ? "Access group for the ${group.name} application" :
        group.type == "pim-dept" ? "PIM elibility for granular roles assigned to the ${group.name} team" :
        group.type == "pim-rbac" ? "PIM elibility for the ${group.role} RBAC role" :
        null # ...Great error handling v2
      )

      membership_rule = (# pwsh $membershipRule equivalent
        group.type == "dept" ? format("(user.accountenabled -eq true) -and (user.department -eq \"%s\")", group.name) :
        group.type == "app" ? format("(user.accountenabled -eq true) -and (user.department -in %s)", group.members) :
        null# Assigned groups don't use membership rules
      )
    }
  }
}

data "azuread_group" "source_dept_for_pim_dept" {# Lookup the DEPT group corresponding to each PIM-DEPT group.
  for_each = {
    for key, group in local.groups_data : key => group
    if group.type == "pim-dept"
  }

  display_name = format("DEPT-%s", lower(replace(each.value.name, " ", "_")))
}

data "azuread_group" "source_depts_for_pim_role" {# Lookup multiple DEPT groups corresponding to each item in members ie [itops|people ops|product]
  for_each = toset(flatten([# Same as foreach($team in ($grp.members).Trim('[]').Split('|')){ in pwsh code
    for group in local.groups_data :
    split("|", trim(group.members, "[]"))
    if group.type == "pim-rbac"
  ]))

  display_name = format("DEPT-%s", lower(replace(each.key, " ", "_")))
}

resource "azuread_group" "tiny_co_groups" {# Creating groups with conditions on assignable or membership depending on its inputs, aka foreach($grp in $tinyCoGroups) equivalent
  for_each = local.processed_groups

  display_name            = each.value.group_name
  prevent_duplicate_names = true# Bonus tf feature instead of checking if group exists first, since Entra can have duplicates and I don't have a policy configured
  description             = each.value.group_description
  security_enabled        = true
  mail_enabled            = false
  mail_nickname           = each.value.group_name
  assignable_to_role      = contains(["pim-dept", "pim-rbac"], local.groups_data[each.key].type)

  members = (# Conditional, since we can't use this property for dynamic membership groups
    startswith(local.groups_data[each.key].type, "pim-") ?
    (
      local.groups_data[each.key].type == "pim-dept" ?
      data.azuread_group.source_dept_for_pim_dept[each.key].members
      :
      flatten([ # Pick out objects separated by the pipes
        for dept in split("|", trim(local.groups_data[each.key].members, "[]")) :
        data.azuread_group.source_depts_for_pim_role[dept].members
      ])
    )
    : null
  )


  dynamic "dynamic_membership" {# logic inception: use a tf dynamic rule to create an azure dynamic rule on where startsWith DEPT- -or APP-
    for_each = startswith(each.value.group_name, "DEPT-") || startswith(each.value.group_name, "APP-") ? [1] : []
    content {
      enabled = true
      rule    = each.value.membership_rule
    }
  }
}