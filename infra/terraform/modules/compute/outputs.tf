output "control_plane_private_ip" {
  value = azurerm_linux_virtual_machine.control_plane.private_ip_address
}
output "control_plane_public_ip" {
  value = azurerm_linux_virtual_machine.control_plane.public_ip_address
}


output "worker_public_ip" {
  value = azurerm_linux_virtual_machine.worker[*].public_ip_address
}

