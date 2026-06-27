resource "azurerm_virtual_network" "main" {
  name = "${var.project_name}-vnet"
  location = var.location
  resource_group_name = var.resource_group_name
  address_space   = ["10.0.0.0/16"]

  tags = {
    name    = "${var.project_name}-vnet"
    project = var.project_name
  }
}

resource "azurerm_subnet" "main" {
  name = "${var.project_name}-subnet"
  resource_group_name = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

