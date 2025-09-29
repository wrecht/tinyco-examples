/* main.tf

This file was used to create the infrastructure for DDG Project 2: TinyCo. 
Specifically, creating the Tailscale environment where I decided to create two vm exit nodes to learn more about tailnet

!! Note:
- I generally wouldn't iterate like this with IaC code in a prod environment. I've also kept variables explicit rather than implied/concatenated to improve readability

!! Design choice: 
- Not completing the Tailscale server config inline, as the objectives for the project cite Linux commandline ability. Done via SSH instead

*/

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~>4.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = "true"
}

# Create rg-tailscale for lifespan of tailscale application including vms, vnets etc.
resource "azurerm_resource_group" "rg" {
  name     = "rg-tailscale"
  location = "East US"
}

# Generate private RSA key
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create public key file
resource "local_file" "public_sshkey_file" {
  filename = "id_rsa.pub"
  content  = tls_private_key.ssh_key.public_key_openssh
}

# Create private key file
resource "local_file" "private_sshkey_file" {
  filename        = "id_rsa.pem"
  content         = tls_private_key.ssh_key.private_key_pem
  file_permission = "0600" # Sets secure file permissions
}

# Create /16 vnets in each region (eastus, uksouth) from tfvars file
resource "azurerm_virtual_network" "vnet" {
  for_each            = var.infrastructure_configs
  name                = each.value.vnet_name
  location            = each.value.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [each.value.vnet_cidr]
}

# Create nsg in each region (eastus, uksouth) to be assigned to regional subnets
resource "azurerm_network_security_group" "nsg" {
  for_each            = var.infrastructure_configs
  name                = each.value.nsg_name
  location            = each.value.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow inbound SSH for initial Tailscale configuration via SSH
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Allow UDP port 41641 to minimize latency as per tailscale docs @ https://tailscale.com/kb/1142/cloud-azure-linux & https://tailscale.com/kb/1082/firewall-ports
  security_rule {
    name                       = "AllowTailscale-DERP"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "41641"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowTailscale-STUN"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "3478"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# Creates a /24 subnet in each regional vnet
resource "azurerm_subnet" "subnet" {
  for_each             = var.infrastructure_configs
  name                 = each.value.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[each.key].name
  address_prefixes     = [each.value.subnet_cidr]
}

# Create a public ip for each vm nic
resource "azurerm_public_ip" "pip" {
  for_each            = var.infrastructure_configs
  name                = each.value.pip_name
  location            = each.value.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create a nic in each regional subnet, for use later by vms
resource "azurerm_network_interface" "nic" {
  for_each            = var.infrastructure_configs
  name                = each.value.nic_name
  location            = each.value.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet[each.key].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[each.key].id
  }
}

# Associate the nsgs to the subnets. !Note: Anti-logical to azurerm_network_security_group.nsg[each.value.nsg_name].id
resource "azurerm_subnet_network_security_group_association" "nsg-snet" {
  for_each                  = var.infrastructure_configs
  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id
}

# Create the tailscale application vms to tfvars specs, assign nics, reuse same keys
resource "azurerm_linux_virtual_machine" "vm" {
  for_each = var.infrastructure_configs

  name                            = each.value.vm_name
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = each.value.location
  size                            = each.value.vm_size
  admin_username                  = each.value.admin_user
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nic[each.key].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = each.value.os_publisher
    offer     = each.value.os_offer
    sku       = each.value.os_sku
    version   = "latest"
  }

  admin_ssh_key {
    username   = each.value.admin_user
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  tags = each.value.tags
}

