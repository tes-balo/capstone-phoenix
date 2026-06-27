output "nsg_id" {
  description = "ID of the cluster security group"
  value       = azurerm_network_security_group.cluster.id
}
