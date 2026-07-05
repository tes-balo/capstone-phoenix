terraform {
  backend "azurerm" {
    resource_group_name  = "capstone-phoenix-rg"
    storage_account_name = "capstonestate1783263425"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
