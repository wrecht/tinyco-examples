locals {
  tiny_co_groups_csv = csvdecode(file("${path.module}/new_groups.csv")) # pwsh Import-Csv equivalent

  groups_data = { # set mapping, no real direct pwsh equivalent
    for group in local.tiny_co_groups_csv : "${group.type}-${group.name != "" ? group.name : group.role}" => group
  }

  processed_groups = { # pwsh function setGroupDetails equivalent
    for key, group in local.groups_data : key => {

      group_name = format("%s%s", # pwsh groupName equivalnet
        group.type == "dept" ? "DEPT-" :
        group.type == "app" ? "APP-" :
        group.type == "pim-dept" ? "PIM-DEPT-" :
        group.type == "pim-rbac" ? "PIM-RBAC-" :
        null, #...Great error handling v1
        lower(replace(group.name != "" ? group.name : group.role, " ", "_"))
      )

      group_description = ( # pwsh $groupDescription equivalent
        group.type == "dept" ? "Dynamic membership group for active members in the ${group.name} team" :
        group.type == "app" ? "Access group for the ${group.name} application" :
        group.type == "pim-dept" ? "PIM elibility for granular roles assigned to the ${group.name} team" :
        group.type == "pim-rbac" ? "PIM elibility for the ${group.role} RBAC role" :
        null # ...Great error handling v2
      )

      membership_rule = ( # pwsh $membershipRule equivalent
        group.type == "dept" ? format("(user.accountenabled -eq true) -and (user.department -eq \"%s\")", group.name) :
        group.type == "app" ? format("(user.accountenabled -eq true) -and (user.department -in %s)", jsonencode(split("|", trim(group.members, "[]")))) :
        null # Assigned groups don't use membership rules
      )
    }
  }
}

data "azuread_group" "source_dept_for_pim_dept" { # Lookup the DEPT group corresponding to each PIM-DEPT group.
  for_each = {
    for key, group in local.groups_data : key => group
    if group.type == "pim-dept"
  }

  display_name = format("DEPT-%s", lower(replace(each.value.name, " ", "_")))
}

data "azuread_group" "source_depts_for_pim_role" { # Lookup multiple DEPT groups corresponding to each item in members ie [itops|people ops|product]
  for_each = toset(flatten([                       # Same as foreach($team in ($grp.members).Trim('[]').Split('|')){ in pwsh code
    for group in local.groups_data :
    split("|", trim(group.members, "[]"))
    if group.type == "pim-rbac"
  ]))

  display_name = format("DEPT-%s", lower(replace(each.key, " ", "_")))
}

resource "azuread_group" "tiny_co_dynamic_groups" { # Splitting dynamic and assigned in to separate blocks to avoid members:null == no membership_rule errors. Assume lack of types argument a contributor
  for_each = {
    for key, group in local.processed_groups : key => group
    if local.groups_data[key].type == "dept" || local.groups_data[key].type == "app"
  }

  display_name            = each.value.group_name
  prevent_duplicate_names = true # Bonus tf feature instead of checking if group exists first, since Entra can have duplicates and I don't have a policy configured
  description             = each.value.group_description
  security_enabled        = true
  mail_enabled            = false
  mail_nickname           = each.value.group_name
  assignable_to_role      = false
  types                   = ["DynamicMembership"]

  dynamic_membership {
    enabled = true
    rule    = each.value.membership_rule
  }

}

resource "azuread_group" "tiny_co_assigned_groups" { # Splitting dynamic and assigned in to separate blocks to avoid members:null == no membership_rule errors. Assume lack of types argument a contributor
  for_each = {
    for key, group in local.processed_groups : key => group
    if startswith(local.groups_data[key].type, "pim-")
  }

  display_name            = each.value.group_name
  prevent_duplicate_names = true
  description             = each.value.group_description
  security_enabled        = true
  mail_enabled            = false
  mail_nickname           = each.value.group_name
  assignable_to_role      = true

  members = ( # Conditional, since we can't use this property for dynamic membership groups
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
}
