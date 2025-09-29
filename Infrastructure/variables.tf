variable "infrastructure_configs" {
  description = "A map of configurations for virtual networks and virtual machines."
  type = map(object({
    location     = string
    vnet_name    = string
    vnet_cidr    = string
    subnet_name  = string
    subnet_cidr  = string
    nsg_name     = string
    pip_name     = string
    nic_name     = string
    vm_name      = string
    vm_size      = string
    admin_user   = string
    os_publisher = string
    os_offer     = string
    os_sku       = string
    tags         = map(string)
  }))
}

/*
# Associate network security groups to regional subnets
resource "azurerm_subnet_network_security_group_association" "nsg-snet" {
for_each = { for config in var.infrastructure_configs : config.location => config }
  subnet_id                 = azurerm_subnet.subnet[each.value.subnet_name].id
  network_security_group_id = azurerm_network_security_group.nsg[each.value.nsg_name].id
}
*/