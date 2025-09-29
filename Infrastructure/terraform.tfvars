infrastructure_configs = {
  eastus = {
    location     = "eastus"
    vnet_name    = "vnet-tailscale-eastus"
    vnet_cidr    = "10.0.0.0/16"
    subnet_name  = "snet-tailscale-eastus"
    subnet_cidr  = "10.0.1.0/24"
    nsg_name     = "nsg-tailscale-eastus"
    pip_name     = "pip-tailscale-eastus-01"
    nic_name     = "nic-tailscale-eastus-01"
    vm_name      = "vm-tailscale-eastus-01"
    vm_size      = "Standard_B2s"
    admin_user   = "tinycoadmin"
    os_publisher = "Canonical"
    os_offer     = "0001-com-ubuntu-server-jammy"
    os_sku       = "22_04-lts-gen2"
    tags = {
      environment = "prod"
      region      = "eastus"
      application = "tailscale"
      os          = "ubuntu"
      owner       = "grp-DEPT-ITOps"
    }
  },
  uksouth = {
    location     = "uksouth"
    vnet_name    = "vnet-tailscale-uksouth"
    vnet_cidr    = "10.1.0.0/16"
    subnet_name  = "snet-tailscale-uksouth"
    subnet_cidr  = "10.1.1.0/24"
    nsg_name     = "nsg-tailscale-uksouth"
    pip_name     = "pip-tailscale-uksouth-01"
    nic_name     = "nic-tailscale-uksouth-01"
    vm_name      = "vm-tailscale-uksouth-01"
    vm_size      = "Standard_B2s"
    admin_user   = "tinycoadmin"
    os_publisher = "Canonical"
    os_offer     = "0001-com-ubuntu-server-jammy"
    os_sku       = "22_04-lts-gen2"
    tags = {
      environment = "prod"
      region      = "uksouth"
      application = "tailscale"
      os          = "ubuntu"
      owner       = "grp-DEPT-ITOps"
    }
  }
}