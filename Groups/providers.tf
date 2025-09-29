terraform {
  required_version = ">= 1.0.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.5.0"
    }
  }
}

provider "azuread" {
  tenant_id = "d79ffdb3-8d8b-40bb-8d8f-dc1c901fd560"
}
