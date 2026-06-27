output "vnet_id" {
  description = "ID of the VNet"
  value       = azurerm_virtual_network.main.id
}

output "subnet_id" {
  description = "ID of the Subnet"
  value       = azurerm_subnet.main.id
}